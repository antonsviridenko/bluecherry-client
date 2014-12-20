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
#include <QDebug>
#include <QMutexLocker>

#include <unistd.h>

// MPlayer OS X VO Protocol
@protocol MPlayerOSXVOProto
- (int) startWithWidth: (bycopy int)width
            withHeight: (bycopy int)height
             withBytes: (bycopy int)bytes
            withAspect: (bycopy int)aspect;
- (void) stop;
- (void) render;
- (void) toggleFullscreen;
- (void) ontop;
@end


@interface VideoRenderer : NSObject <MPlayerOSXVOProto> {
    NSString *m_sharedBufferName;
    MplVideoWidget *m_widget;
    NSThread *m_thread;
}

- (id)initWithWidget:(MplVideoWidget *)aWidget
sharedBufferName:(NSString *)aName
@end


@interface VideoRenderer ()
- (void)connect;
- (void)disconnect;
@end

#pragma mark -

@implementation VideoRenderer

- (id)initWithWidget:(MplVideoWidget *)aWidget
sharedBufferName:(NSString *)aName
{
    if (!(self = [super init]))
    {
        return nil;
    }

    m_sharedBufferName = aName;
    m_widget = aWidget;

    m_thread = [[NSThread alloc] initWithTarget:self
                                    selector:@selector(connect)
                                       object:nil];

    [m_thread start];

    return self;
}

- (void)dealloc
{
    if ([m_thread isExecuting])
    {
        [self performSelector:@selector(disconnect)
                     onThread:m_thread
                   withObject:nil
                waitUntilDone:YES];
    }

    while ([m_thread isExecuting])
    {
    }

    [m_sharedBufferName release];
    [super dealloc];
}

- (void)connect
{
    //@autoreleasepool
    //{
        //[NSConnection serviceConnectionWithName:m_sharedBufferName
         //                            rootObject:self];

        NSConnection *serverConnection = [NSConnection new];
        [serverConnection setRootObject:self];
        [serverConnection registerName:connectionName];

        CFRunLoopRun();

        [serverConnection release];
   //}
}

- (void)disconnect
{
    CFRunLoopStop(CFRunLoopGetCurrent());
    [self stop];
}

#pragma mark -
#pragma mark MPlayerOSXVOProto

- (int)startWithWidth:(bycopy int)width
           withHeight:(bycopy int)height
            withBytes:(bycopy int)bytes
           withAspect:(bycopy int)aspect
{
    m_widget->initSharedMem([m_sharedBufferName UTF8String], width, height, bytes);

    return 0;
}

- (void)stop
{
    m_widget->stop();
}

- (void)render
{
    m_widget->getFrame();
}

- (void)toggleFullscreen
{

}

- (void)ontop
{

}

@end


void MplVideoWidget::getFrame()
{
    if (!m_sharedBuffer || !m_frontBuffer || !m_backBuffer)
        return;

    SwsContext * ctx = sws_getContext(m_frameWidth, m_frameHeight,
                                      m_pixelFormat, m_frameWidth, m_frameHeight,
                                      AV_PIX_FMT_ARGB, 0, 0, 0, 0);


    uint8_t * inData[1] = { m_sharedBuffer };
    int inLinesize[1] = { m_bpp * m_frameWidth };
    int outLinesize[1];
    uint8_t *outData[1] = { m_backBuffer };
    sws_scale(ctx, inData, inLinesize, 0, m_frameHeight, outData, outLinesize);

    //switch buffers
    m_frameLock.lock();
    unsigned char *tmp = m_frontBuffer;
    m_frontBuffer = m_backBuffer;
    m_backBuffer = tmp;
    m_frameLock.unlock();

    QMetaObject::invokeMethod(m_viewport, "update", Qt::QueuedConnection);
}

void MplVideoWidget::stop()
{
    QMutexLocker locker(&m_frameLock);

    qDebug() << "MplVideoWidget::stop()\n";

    free(m_backBuffer);
    m_backBuffer = NULL;

    free(m_frontBuffer);
    m_frontBuffer = NULL;

    if (m_sharedBuffer)
    {
        munmap(m_sharedBuffer, m_bufferSize);
        m_sharedBuffer = NULL;
    }

    m_bufferSize = 0;
}

void MplVideoWidget::initSharedMem(const char *bufferName, int width, int height, int bpp)
{
    QMutexLocker locker(&m_frameLock);

    qDebug() << "initSharedMem()\n";

    int shbf = shm_open(bufferName, O_RDONLY, S_IRUSR);

    if (shbf == -1)
    {
        qDebug() << "Failed to open shared memory buffer " << bufferName << "\n";
        return;
    }

    m_bufferSize = width * height * bpp;
    m_frameWidth = width;
    m_frameHeight = height;
    m_bpp = bpp;


    if (m_sharedBuffer)
    {
        munmap(m_sharedBuffer, m_bufferSize);
    }
    m_sharedBuffer = (unsigned char*) mmap(NULL, m_bufferSize, PROT_READ, MAP_SHARED, shbf, 0);

    ::close(shbf);

    if (m_sharedBuffer == MAP_FAILED)
    {
        qDebug() << "Unable to allocate shared buffer for mplayer\n";
        return;
    }

    if (m_frontBuffer)
    {
        free(m_frontBuffer);
    }

    if (m_backBuffer)
    {
        free(m_backBuffer);
    }

    m_frontBuffer = (unsigned char*) malloc(m_bufferSize);
    m_backBuffer = (unsigned char*) malloc(m_bufferSize);

    switch (bpp)
    {
    case 3:
        m_pixelFormat = AV_PIX_FMT_RGB24;//k24RGBPixelFormat;
        break;
    case 4:
        m_pixelFormat = AV_PIX_FMT_BGRA ;//k32BGRAPixelFormat;
        break;
    default:
        m_pixelFormat = AV_PIX_FMT_YUYV422 ;//kYUVSPixelFormat;
    }
}

MplVideoWidget::~MplVideoWidget()
{
    stop();

    [m_renderer dealloc];
}

MplVideoWidget::MplVideoWidget(QWidget *parent)
    : VideoWidget(parent),
      m_viewport(0),
      m_frameWidth(-1),
      m_frameHeight(-1),
      m_normalFrameStyle(0),
      m_sharedBuffer(0),
      m_bufferSize(0),
      m_frontBuffer(0),
      m_backBuffer(0)
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

    /*m_renderer = */(void) [[VideoRenderer alloc] initWithWidget:this
   sharedBufferName:[[NSString alloc] initWithBytes:"bceventmplayer"
                    length:14
                    encoding:NSASCIIStringEncoding]];
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

bool MplVideoWidget::eventFilter(QObject *obj, QEvent *ev)
{
    Q_ASSERT(obj == m_viewport);

    if (ev->type() != QEvent::Paint)
        return QFrame::eventFilter(obj, ev);

    QPainter p(m_viewport);

    p.setBackground(QColor(Qt::black));

    m_frameLock.lock();

    if (!m_frontBuffer)
    {
        p.fillRect(rect(), Qt::black);
        m_frameLock.unlock();
        return true;
    }

    QImage frame = QImage(m_frontBuffer, m_frameWidth, m_frameHeight, QImage::Format_ARGB32);

    QRect r = rect();
    p.eraseRect(r);
    QSize scaledSize = frame.size();
    scaledSize.scale(r.size(), Qt::KeepAspectRatio);
    r.adjust((r.width() - scaledSize.width()) / 2, (r.height() - scaledSize.height()) / 2, 0, 0);
    r.setSize(scaledSize);
    p.drawImage(r, frame);

    m_frameLock.unlock();
    return true;
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
    m_viewport->installEventFilter(this);
    m_viewport->setStyleSheet(QLatin1String("background-color:black;"));
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
        //update();
    }

    QSettings settings;
    if (settings.value(QLatin1String("ui/disableScreensaver/onFullscreen")).toBool())
        bcApp->setScreensaverInhibited(on);
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
