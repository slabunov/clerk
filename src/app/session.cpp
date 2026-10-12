#include "app/session.hpp"

#include "platform/files.hpp"

#include <QMetaObject>

#include <algorithm>
#include <array>
#include <cstddef>
#include <memory>

namespace {
    QString kindText(const clerk::Kind k) {
        static const std::array names{
            QObject::tr("Same file"), QObject::tr("Same pixels"), QObject::tr("Saved again"),
            QObject::tr("Resized copy"), QObject::tr("Cropped copy"), QObject::tr("Same moment"),
            QObject::tr("Same place and light")
        };
        return names[std::to_underlying(k)];
    }

    QVariantMap criterion(const clerk::Evidence &e) {
        using enum clerk::Criterion;
        static const std::array labels{
            QObject::tr("File content"), QObject::tr("Pixels"), QObject::tr("Pixel difference"),
            QObject::tr("Visual similarity"), QObject::tr("Background colours"), QObject::tr("Outfit colours")
        };

        QString value;
        float   bar = std::clamp(e.contribution / 4.f, -1.f, 1.f);
        switch (e.criterion) {
            case FileBytes:
            case Pixels:
                value = QObject::tr("identical");
                bar = 1.f;
                break;
            case PixelDelta: value = QObject::tr("%1 dB").arg(e.measured, 0, 'f', 1);
                break;
            case FeaturePrint: value = QObject::tr("distance %1").arg(e.measured, 0, 'f', 2);
                break;
            case BackgroundColour:
            case Person: value = QObject::tr("difference %1").arg(e.measured, 0, 'f', 2);
                break;
        }
        return {{"label", labels[std::to_underlying(e.criterion)]}, {"value", value}, {"bar", bar}};
    }
} // namespace

Session::Session(QObject *parent) : QObject(parent) {
}

bool Session::reduceMotion() {
    return clerk::reduceMotion();
}

void Session::setState(const State s) {
    state_ = s;
    emit stateChanged();
}

const std::vector<clerk::Group> &Session::level(const int l) const {
    CLERK_ASSERT(l >= 0 && l < 3);
    return l == 0 ? result_.exact : l == 1 ? result_.similar : result_.related;
}

QVariantList Session::trash() const {
    QVariantList ids;
    for (const auto id: decisions_.trash) {
        ids.append(static_cast<int>(id));
    }
    return ids;
}

qint64 Session::trashBytes() const {
    qint64 bytes = 0;
    for (const auto id: decisions_.trash) {
        bytes += static_cast<qint64>(scan_.media[id].stamp.bytes);
    }
    return bytes;
}

void Session::scan(const QUrl &folder) {
    const std::filesystem::path dir = folder.toLocalFile().toStdString();
    if (std::error_code ec; folder.isEmpty() || !std::filesystem::is_directory(dir, ec)) {
        error_ = tr("Select a folder, not a file.");
        emit stateChanged();
        return;
    }

    std::vector<std::filesystem::path> paths;
    try {
        paths = clerk::list(dir);
    } catch (const std::filesystem::filesystem_error &e) {
        spdlog::warn("Cannot list {}: {}", dir.string(), e.what());
        error_ = tr("Cannot open this folder.");
        emit stateChanged();
        return;
    }
    if (paths.empty()) {
        error_ = tr("This folder has no files.");
        emit stateChanged();
        return;
    }

    folder_ = folder;
    files_.clear();
    for (const auto &p: paths) {
        files_ << QString::fromStdString(p.string());
    }
    fileState_ = QVariantList(static_cast<qsizetype>(paths.size()), 0);
    stage_ = 0;
    done_ = 0;
    error_.clear();

    const int generation = ++generation_;
    emit filesChanged();
    emit progressChanged();
    setState(Scanning);

    worker_ = std::jthread([this, generation, paths = std::move(paths)](const std::stop_token &stop) {
        const auto post = [this, generation](const auto &f) {
            QMetaObject::invokeMethod(this, [this, generation, f] {
                if (generation == generation_) {
                    f();
                }
            }, Qt::QueuedConnection);
        };

        const auto onFile = [&](std::size_t i, bool finished) {
            post([this, i, finished] {
                fileState_[static_cast<qsizetype>(i)] = finished ? 2 : 1;
                done_ += finished;
                emit progressChanged();
            });
        };

        auto scan = std::make_shared<clerk::Scan>(
            clerk::analyze(paths, stop, onFile));
        if (stop.stop_requested()) {
            return;
        }
        post([this] {
            stage_ = 1;
            emit progressChanged();
        });

        const auto pairs = clerk::assessAll(scan->media, scan->psnr);
        post([this] {
            stage_ = 2;
            emit progressChanged();
        });
        auto groups = std::make_shared<clerk::Groups>(clerk::group(scan->media, pairs));
        post([this, scan, groups] {
            finish(std::move(*scan), std::move(*groups));
        });
    });
}

void Session::finish(clerk::Scan scan, clerk::Groups groups) {
    scan_ = std::move(scan);
    result_ = std::move(groups);
    decisions_ = {};

    items_.clear();
    for (const clerk::Media &m: scan_.media) {
        items_.append(QVariantMap{
            {"id", static_cast<int>(m.id.value)},
            {"path", QString::fromStdString(m.path.string())},
            {"url", QUrl::fromLocalFile(QString::fromStdString(m.path.string()))},
            {"name", QString::fromStdString(m.path.filename().string())},
            {"video", m.type == clerk::MediaType::Video},
            {"width", m.width},
            {"height", m.height},
            {"seconds", m.seconds},
            {"bytes", static_cast<qint64>(m.stamp.bytes)},
        });
    }

    groups_.clear();
    for (int l = 0; l < 3; ++l) {
        QVariantList list;
        for (const clerk::Group &g: level(l)) {
            QVariantList members;
            QVariantMap  links;
            for (const auto [value]: g.members) {
                members.append(static_cast<int>(value));
            }
            for (const clerk::Match &e: g.edges) {
                links.insert(QString::number(e.a.value),
                             QVariantMap{{"confidence", e.confidence.value}, {"kind", kindText(e.kind)}});
            }
            list.append(QVariantMap{
                {"members", members}, {"reference", static_cast<int>(g.reference.value)}, {"links", links}
            });
        }
        groups_.append(QVariant(list));
    }

    skipped_.clear();
    for (const auto &[path, reason]: scan_.skipped) {
        skipped_.append(QVariantMap{
            {"name", QString::fromStdString(path.filename().string())}, {"reason", QString::fromStdString(reason)}
        });
    }

    spdlog::info("Groups: {} exact, {} similar, {} related", result_.exact.size(), result_.similar.size(),
                 result_.related.size());
    emit resultsChanged();
    emit trashChanged();
    setState(Results);
}

void Session::cancel() {
    ++generation_;
    worker_.request_stop();
    setState(Start);
}

void Session::reset() {
    ++generation_;
    worker_.request_stop();
    error_.clear();
    setState(Start);
}

void Session::toggle(const int id) {
    CLERK_ASSERT(id >= 0 && static_cast<std::size_t>(id) < scan_.media.size());
    decisions_.toggle(clerk::MediaId{static_cast<std::uint32_t>(id)});
    emit trashChanged();
}

void Session::keepBestQuality(const int l, const int index) {
    const auto &groups = level(l);
    CLERK_ASSERT(index >= 0 && static_cast<std::size_t>(index) < groups.size());
    decisions_.keepBestQuality(groups[static_cast<std::size_t>(index)]);
    emit trashChanged();
}

void Session::keepBestQualityAll(const int l) {
    for (const clerk::Group &g: level(l)) {
        decisions_.keepBestQuality(g);
    }
    emit trashChanged();
}

QVariantMap Session::details(const int l, const int index, const int id) const {
    const auto &groups = level(l);
    CLERK_ASSERT(index >= 0 && static_cast<std::size_t>(index) < groups.size());
    CLERK_ASSERT(id >= 0 && static_cast<std::size_t>(id) < scan_.media.size());
    const clerk::Group &g = groups[static_cast<std::size_t>(index)];
    const clerk::Media &m = scan_.media[static_cast<std::size_t>(id)];

    QVariantMap d = items_[id].toMap();
    const auto &q = m.quality;
    d["quality"] = QVariantList{
        QVariantMap{{"label", tr("Resolution")}, {"value", tr("%1 MP").arg(q.megapixels, 0, 'f', 1)}},
        QVariantMap{
            {"label", m.type == clerk::MediaType::Video ? tr("Bits per pixel per second") : tr("Bits per pixel")},
            {"value", QString::number(q.bitsPerPixel, 'f', 2)}
        },
        QVariantMap{{"label", tr("Sharpness")}, {"value", QString::number(q.sharpness, 'f', 0)}},
        QVariantMap{{"label", tr("Pure black or white")}, {"value", tr("%1 %").arg(q.clipped * 100, 0, 'f', 1)}},
        QVariantMap{{"label", tr("Aesthetics (Vision)")}, {"value", QString::number(q.aesthetics, 'f', 2)}},
    };
    d["score"] = q.score();
    d["reference"] = g.reference.value == static_cast<std::uint32_t>(id);
    d["level"] = l;

    const auto edge = std::ranges::find_if(g.edges, [&](const clerk::Match &e) {
        return e.a.value == static_cast<std::uint32_t>(id);
    });
    if (edge != g.edges.end()) {
        QVariantList criteria;
        for (const clerk::Evidence &e: edge->evidence) {
            criteria.append(criterion(e));
        }
        d["kind"] = kindText(edge->kind);
        d["confidence"] = edge->confidence.value;
        d["comparedWith"] = QString::fromStdString(scan_.media[edge->b.value].path.filename().string());
        d["criteria"] = criteria;
    }
    return d;
}

void Session::moveToTrash() {
    trashed_.clear();
    QVariantList failed;
    qint64       bytes = 0;

    for (const auto id: decisions_.trash) {
        const clerk::Media &m = scan_.media[id];
        if (auto place = clerk::moveToTrash(m.path, m.stamp)) {
            spdlog::info("Moved to the Trash: {}", m.path.string());
            trashed_.emplace_back(std::move(*place), m.path);
            bytes += static_cast<qint64>(m.stamp.bytes);
        } else {
            spdlog::warn("Not moved to the Trash: {} ({})", m.path.string(), place.error());
            failed.append(QVariantMap{
                {"name", QString::fromStdString(m.path.filename().string())},
                {"reason", QString::fromStdString(place.error())}
            });
        }
    }
    decisions_ = {};
    report_ = {{"moved", static_cast<int>(trashed_.size())}, {"bytes", bytes}, {"failed", failed}, {"restored", -1}};
    emit trashChanged();
    setState(Done);
}

void Session::undo() {
    QVariantList failed;
    int          restored = 0;
    for (const auto &[trashed, original]: trashed_) {
        if (auto ok = clerk::putBack(trashed, original)) {
            spdlog::info("Put back: {}", original.string());
            ++restored;
        } else {
            spdlog::warn("Cannot put back {}: {}", original.string(), ok.error());
            failed.append(QVariantMap{
                {"name", QString::fromStdString(original.filename().string())},
                {"reason", QString::fromStdString(ok.error())}
            });
        }
    }
    trashed_.clear();
    report_ = {{"moved", 0}, {"bytes", 0}, {"failed", failed}, {"restored", restored}};
    emit stateChanged();
}
