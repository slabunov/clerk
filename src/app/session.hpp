#pragma once

#include "core/decisions.hpp"
#include "core/match.hpp"
#include "platform/analyze.hpp"

#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <filesystem>
#include <thread>
#include <utility>
#include <vector>

class Session : public QObject {
    Q_OBJECT
    QML_ELEMENT

    QML_SINGLETON

    Q_PROPERTY(int state READ state NOTIFY stateChanged)

    Q_PROPERTY(QString error READ error NOTIFY stateChanged)

    Q_PROPERTY(QVariantMap report READ report NOTIFY stateChanged)

    Q_PROPERTY(QUrl folder READ folder NOTIFY stateChanged)

    Q_PROPERTY(QStringList files READ files NOTIFY filesChanged)

    Q_PROPERTY(QVariantList fileState READ fileState NOTIFY progressChanged)

    Q_PROPERTY(int stage READ stage NOTIFY progressChanged)

    Q_PROPERTY(int done READ done NOTIFY progressChanged)

    Q_PROPERTY(QVariantList items READ items NOTIFY resultsChanged)

    Q_PROPERTY(QVariantList groups READ groups NOTIFY resultsChanged)

    Q_PROPERTY(QVariantList skipped READ skipped NOTIFY resultsChanged)

    Q_PROPERTY(QVariantList trash READ trash NOTIFY trashChanged)

    Q_PROPERTY(qint64 trashBytes READ trashBytes NOTIFY trashChanged)

    Q_PROPERTY(bool reduceMotion READ reduceMotion CONSTANT)

public:
    enum State { Start, Scanning, Results, Done };

    Q_ENUM(State)

    explicit Session(QObject *parent = nullptr);

    [[nodiscard]] int          state() const { return state_; }
    [[nodiscard]] QString      error() const { return error_; }
    [[nodiscard]] QVariantMap  report() const { return report_; }
    [[nodiscard]] QUrl         folder() const { return folder_; }
    [[nodiscard]] QStringList  files() const { return files_; }
    [[nodiscard]] QVariantList fileState() const { return fileState_; }
    [[nodiscard]] int          stage() const { return stage_; }
    [[nodiscard]] int          done() const { return done_; }
    [[nodiscard]] QVariantList items() const { return items_; }
    [[nodiscard]] QVariantList groups() const { return groups_; }
    [[nodiscard]] QVariantList skipped() const { return skipped_; }

    [[nodiscard]] QVariantList trash() const;

    [[nodiscard]] qint64 trashBytes() const;

    [[nodiscard]] static bool reduceMotion();

    Q_INVOKABLE void scan(const QUrl &folder);

    Q_INVOKABLE void cancel();

    Q_INVOKABLE void reset();

    Q_INVOKABLE void toggle(int id);

    Q_INVOKABLE void keepBestQuality(int level, int index);

    Q_INVOKABLE void keepBestQualityAll(int level);

    [[nodiscard]] Q_INVOKABLE QVariantMap details(int level, int index, int id) const;

    Q_INVOKABLE void moveToTrash();

    Q_INVOKABLE void undo();

signals:
    void stateChanged();

    void filesChanged();

    void progressChanged();

    void resultsChanged();

    void trashChanged();

private:
    void setState(State s);

    void finish(clerk::Scan scan, clerk::Groups groups);

    [[nodiscard]] const std::vector<clerk::Group> &level(int l) const;

    State        state_ = Start;
    QString      error_;
    QVariantMap  report_;
    QUrl         folder_;
    QStringList  files_;
    QVariantList fileState_; // 0 waiting, 1 in progress, 2 done
    int          stage_ = 0; // 0 examine, 1 compare, 2 group
    int          done_ = 0;
    QVariantList items_, groups_, skipped_;

    clerk::Scan                                                           scan_;
    clerk::Groups                                                         result_;
    clerk::Decisions                                                      decisions_;
    std::vector<std::pair<std::filesystem::path, std::filesystem::path> > trashed_;

    int          generation_ = 0;
    std::jthread worker_;
};
