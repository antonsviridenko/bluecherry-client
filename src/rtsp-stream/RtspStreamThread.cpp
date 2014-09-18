/*
 * Copyright 2010-2013 Bluecherry
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "RtspStreamThread.h"
#include "RtspStreamWorker.h"
#include "core/BluecherryApp.h"
#include "core/LoggableUrl.h"
#include <QDebug>
#include <QThread>
#include <QUrl>

RtspStreamThread::RtspStreamThread(QObject *parent) :
        QObject(parent),
        m_thread(NULL), m_worker(NULL),
        m_workerMutex(QMutex::Recursive), m_isRunning(false)
{
}

RtspStreamThread::~RtspStreamThread()
{
    stop();
}

void RtspStreamThread::start(const QUrl &url)
{
    QMutexLocker locker(&m_workerMutex);

    qDebug() << Q_FUNC_INFO << LoggableUrl(url);

    if (!m_worker)
    {
        Q_ASSERT(!m_thread);
        m_thread = new QThread();

        RtspStreamWorker *worker = new RtspStreamWorker();
        m_worker = worker;

        worker->moveToThread(m_thread);

        m_worker->setUrl(url);

        connect(m_thread, SIGNAL(started()), m_worker, SLOT(run()));
        connect(m_worker, SIGNAL(fatalError(QString)), this, SIGNAL(fatalError(QString)));
        connect(m_worker, SIGNAL(bytesDownloaded(uint)), bcApp->globalRate, SLOT(addSampleValue(uint)));

        m_thread->start();
    }
    else
        m_worker->metaObject()->invokeMethod(m_worker, "run");

    m_isRunning = true;
}

void RtspStreamThread::stop()
{
    QMutexLocker locker(&m_workerMutex);

    m_isRunning = false;

    if (m_worker)
    {
        m_worker->stop();
        m_thread->wait(ULONG_MAX);

        delete m_worker;
        delete m_thread;
        m_worker = NULL;
        m_thread = NULL;
    }

  //  Q_ASSERT(!m_thread);
}

void RtspStreamThread::setPaused(bool paused)
{
    QMutexLocker locker(&m_workerMutex);

    m_worker->setPaused(paused);
}

bool RtspStreamThread::hasWorker()
{
    QMutexLocker locker(&m_workerMutex);

    return m_worker;
}

bool RtspStreamThread::isRunning() const
{
    return m_isRunning;
}

void RtspStreamThread::setAutoDeinterlacing(bool autoDeinterlacing)
{
    QMutexLocker locker(&m_workerMutex);

    if (hasWorker())
        m_worker->setAutoDeinterlacing(autoDeinterlacing);
}

RtspStreamFrame * RtspStreamThread::frameToDisplay()
{
    QMutexLocker locker(&m_workerMutex);

    if (hasWorker())
        return m_worker->frameToDisplay();
    else
        return 0;
}
