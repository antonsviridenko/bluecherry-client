/*
 * Copyright 2010-2014 Bluecherry
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

#include "MplVideoWidget.h"
#include "MplVideoPlayerBackend.h"
#include "core/BluecherryApp.h"
#include <QWidget>
#include <QImage>
#include <QApplication>
#include <QSettings>
#include <QMouseEvent>


MplVideoWidget::~MplVideoWidget()
{

}

MplVideoWidget::MplVideoWidget(QWidget *parent)
    : VideoWidget(parent),
      m_viewport(0),
      m_frameWidth(-1),
      m_frameHeight(-1),
      m_normalFrameStyle(0)
{
    setAutoFillBackground(false);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);

    setMinimumSize(320, 240);
    setFrameStyle(QFrame::Sunken | QFrame::Panel);
    QPalette p = palette();
    p.setColor(QPalette::Window, Qt::black);
    p.setColor(QPalette::WindowText, Qt::white);
    setPalette(p);

    setViewport(new QWidget);
}

void MplVideoWidget::initVideo(VideoPlayerBackend *videoPlayerBackend)
{
    MplVideoPlayerBackend *backend = reinterpret_cast<MplVideoPlayerBackend *>(videoPlayerBackend);

    backend->setWindowId((quint64) m_viewport->winId());
}

void MplVideoWidget::clearVideo()
{
    m_frameWidth = -1;
    m_frameHeight = -1;
}

void MplVideoWidget::setViewport(QWidget *w)
{
    if (m_viewport)
    {
        m_viewport->removeEventFilter(this);
        m_viewport->deleteLater();
    }

    m_viewport = w;
    m_viewport->setParent(this);
    m_viewport->setGeometry(contentsRect());
    m_viewport->setAutoFillBackground(false);
    m_viewport->setAttribute(Qt::WA_OpaquePaintEvent);
    //m_viewport->installEventFilter(this);
    m_viewport->show();
}

QSize MplVideoWidget::sizeHint() const
{
    return QSize(m_frameWidth, m_frameHeight);
}

void MplVideoWidget::setOverlayMessage(const QString &message)
{
    if (message == m_overlayMsg)
        return;

    m_overlayMsg = message;
    m_viewport->update();
}

void MplVideoWidget::setFullScreen(bool on)
{
    if (on)
    {
        setWindowFlags(windowFlags() | Qt::Window);
        m_normalFrameStyle = frameStyle();
        setFrameStyle(QFrame::NoFrame);
        showFullScreen();
    }
    else
    {
        setWindowFlags(windowFlags() & ~Qt::Window);
        setFrameStyle(m_normalFrameStyle);
        showNormal();
    }

    QSettings settings;
    if (settings.value(QLatin1String("ui/disableScreensaver/onFullscreen")).toBool())
        bcApp->setScreensaverInhibited(on);
}

QImage MplVideoWidget::currentFrame()
{
    //implement me
    return QImage();
}

void MplVideoWidget::resizeEvent(QResizeEvent *ev)
{
    QFrame::resizeEvent(ev);
    m_viewport->setGeometry(contentsRect());
}

void MplVideoWidget::mouseDoubleClickEvent(QMouseEvent *ev)
{
    ev->accept();
    toggleFullScreen();
}

void MplVideoWidget::keyPressEvent(QKeyEvent *ev)
{
    if (ev->modifiers() != 0)
        return;

    switch (ev->key())
    {
    case Qt::Key_Escape:
        setFullScreen(false);
        break;
    default:
        return;
    }

    ev->accept();
}
