#include "app/session.hpp"
#include "platform/analyze.hpp"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickImageProvider>
#include <QQuickStyle>
#include <QUrl>

#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>

#include <cstdlib>
#include <filesystem>
#include <memory>

namespace {
    // image://thumb/<percent-encoded path>
    class Thumbnails : public QQuickImageProvider {
    public:
        Thumbnails() : QQuickImageProvider(Image, ForceAsynchronousImageLoading) {
        }

        QImage requestImage(const QString &id, QSize *size, const QSize &requested) override {
            const std::filesystem::path path = QUrl::fromPercentEncoding(id.toUtf8()).toStdString();
            const auto side = static_cast<std::size_t>(std::max({requested.width(), requested.height(), 128}));
            const auto picture = clerk::thumbnail(path, side);
            if (!picture) {
                spdlog::warn("No preview for {}: {}", path.filename().string(), picture.error());
                return {};
            }
            const QImage image(picture->rgba.data(),
                               static_cast<int>(picture->width),
                               static_cast<int>(picture->height),
                               static_cast<int>(picture->width * 4),
                               QImage::Format_RGBA8888_Premultiplied);
            if (size) {
                *size = image.size();
            }
            return image.copy();
        }
    };

    void startLog() {
        const auto dir = std::filesystem::path{std::getenv("HOME")} / "Library/Logs/Clerk";
        std::filesystem::create_directories(dir);
        auto logger = std::make_shared<spdlog::logger>("clerk",
                                                       spdlog::sinks_init_list{
                                                           std::make_shared<spdlog::sinks::stdout_color_sink_mt>(),
                                                           std::make_shared<spdlog::sinks::basic_file_sink_mt>(
                                                               (dir / "clerk.log").string(), true
                                                           ),
                                                       });
        logger->flush_on(spdlog::level::warn);
        spdlog::set_default_logger(std::move(logger));
    }
} // namespace

int main(int argc, char *argv[]) {
    startLog();
    const QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName("Clerk");
    QQuickStyle::setStyle("Material");

    QQmlApplicationEngine engine;
    engine.addImageProvider("thumb", new Thumbnails);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] {
        spdlog::critical("Cannot load the interface");
        QCoreApplication::exit(1);
    }, Qt::QueuedConnection);
    engine.loadFromModule("Clerk", "Main");

    if (const QStringList args = QGuiApplication::arguments(); args.size() > 1) {
        // Clerk <folder>
        engine.singletonInstance<Session *>("Clerk", "Session")->scan(QUrl::fromLocalFile(args[1]));
    }
    return QGuiApplication::exec();
}
