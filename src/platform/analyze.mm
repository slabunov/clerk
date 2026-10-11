#include "platform/analyze.hpp"
#include "platform/files.hpp"

#include "core/features.hpp"
#include "core/thresholds.hpp"

#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Vision/Vision.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <expected>
#include <limits>
#include <memory>
#include <utility>

namespace clerk {
    namespace {
        constexpr std::size_t kWorkingSize = 512;
        constexpr double      kFrameStep = 1.0;
        constexpr std::size_t kMaxFrames = 120;

        struct CFReleaser {
            void operator()(CFTypeRef r) const { if (r) CFRelease(r); }
        };

        template<class T>
        using CF = std::unique_ptr<std::remove_pointer_t<T>, CFReleaser>;

        using Error = std::string;

        struct Bitmap {
            std::size_t               rows = 0, cols = 0;
            std::vector<std::uint8_t> px;

            [[nodiscard]] Rgba view() const {
                return Rgba{px.data(), rows, cols};
            }
        };

        Bitmap render(CGImageRef img, std::size_t cols, std::size_t rows) {
            Bitmap              b{rows, cols, std::vector<std::uint8_t>(rows * cols * 4)};
            CF<CGColorSpaceRef> space{CGColorSpaceCreateWithName(kCGColorSpaceSRGB)};
            CF<CGContextRef>    ctx{
                CGBitmapContextCreate(b.px.data(), cols, rows, 8, cols * 4, space.get(), kCGImageAlphaPremultipliedLast)
            };
            CLERK_ASSERT(ctx != nullptr);
            CGContextSetInterpolationQuality(ctx.get(), kCGInterpolationHigh);
            CGContextDrawImage(ctx.get(), CGRectMake(0, 0, CGFloat(cols), CGFloat(rows)), img);
            return b;
        }

        CF<CGImageRef> borrow(const Bitmap &b) {
            CF<CGColorSpaceRef>   space{CGColorSpaceCreateWithName(kCGColorSpaceSRGB)};
            CF<CGDataProviderRef> data{CGDataProviderCreateWithData(nullptr, b.px.data(), b.px.size(), nullptr)};
            return CF<CGImageRef>{
                CGImageCreate(b.cols, b.rows, 8, 32, b.cols * 4, space.get(), kCGImageAlphaPremultipliedLast,
                              data.get(), nullptr, false, kCGRenderingIntentDefault)
            };
        }

        Bitmap working(CGImageRef img) {
            const std::size_t cols = CGImageGetWidth(img), rows = CGImageGetHeight(img);
            const double      scale = std::min(1.0, double(kWorkingSize) / double(std::max(cols, rows)));
            return render(img, std::size_t(std::lround(double(cols) * scale)),
                          std::size_t(std::lround(double(rows) * scale)));
        }

        Digest sha256(const void *data, std::size_t size) {
            CLERK_ASSERT(size <= std::numeric_limits<CC_LONG>::max());
            Digest d;
            CC_SHA256(data, CC_LONG(size), d.data());
            return d;
        }

        CF<CGImageRef> decodeFull(NSData *bytes) {
            CF<CGImageSourceRef> src{CGImageSourceCreateWithData((__bridge CFDataRef)bytes, nullptr)};
            if (!src || CGImageSourceGetCount(src.get()) == 0) return nullptr;
            NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src.get(), 0, nullptr));
            const long    longEdge = std::max([props[(id) kCGImagePropertyPixelWidth]longValue],
                                              [props[(id) kCGImagePropertyPixelHeight]longValue]);
            if (longEdge <= 0) return nullptr;
            NSDictionary *options = @ {
                (id) kCGImageSourceCreateThumbnailFromImageAlways: @ YES,
                (id) kCGImageSourceCreateThumbnailWithTransform: @ YES,
                (id) kCGImageSourceThumbnailMaxPixelSize: @ (longEdge),
                (id) kCGImageSourceShouldCacheImmediately: @ YES,
            };
            return CF<CGImageRef>{CGImageSourceCreateThumbnailAtIndex(src.get(), 0, (__bridge CFDictionaryRef)options)};
        }

        std::expected<Print, Error> printOf(VNFeaturePrintObservation *o) {
            if (o == nil) return std::unexpected("Vision returned no feature print");
            CLERK_ASSERT(o.elementType == VNElementTypeFloat && o.elementCount == kPrintSize);
            Print p;
            std::memcpy(p.data(), o.data.bytes, sizeof p);
            return p;
        }

        std::vector<std::uint8_t> maskOf(VNPixelBufferObservation *o, std::size_t rows, std::size_t cols) {
            std::vector<std::uint8_t> mask(rows * cols, 0);
            if (o == nil) return mask; // no person
            CVPixelBufferRef pb = o.pixelBuffer;
            CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
            const auto *      base = static_cast<const std::uint8_t *>(CVPixelBufferGetBaseAddress(pb));
            const std::size_t mw = CVPixelBufferGetWidth(pb), mh = CVPixelBufferGetHeight(pb), stride =
                    CVPixelBufferGetBytesPerRow(pb);
            for (std::size_t y = 0; y < rows; ++y)
                for (std::size_t x = 0; x < cols; ++x)
                    mask[y * cols + x] = base[(y * mh / rows) * stride + x * mw / cols];
            CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
            return mask;
        }

        struct Described {
            Frame frame;
            float aesthetics;
        };

        std::expected<Described, Error> describeFrame(const Bitmap &work) {
            if (std::min(work.rows, work.cols) < kMinSide) return std::unexpected("picture is smaller than 64 px");
            CF<CGImageRef> img = borrow(work);
            auto *         print = [VNGenerateImageFeaturePrintRequest new];
            print.revision = VNGenerateImageFeaturePrintRequestRevision2;
            auto *person = [VNGeneratePersonSegmentationRequest new];
            person.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
            person.outputPixelFormat = kCVPixelFormatType_OneComponent8;
            auto *   aesthetics = [VNCalculateImageAestheticsScoresRequest new];
            NSError *error = nil;
            if (! [[[VNImageRequestHandler alloc] initWithCGImage:img.get() options:@ {
            }] performRequests:@ [ print, person, aesthetics ]



        error:
            &error])
            return std::unexpected(Error{error.localizedDescription.UTF8String});

            auto whole = printOf(print.results.firstObject);
            if (!whole) return std::unexpected(whole.error());
            const auto mask = maskOf(person.results.firstObject, work.rows, work.cols);
            return Described{
                describe(work.view(), Mask{mask.data(), work.rows, work.cols}, *whole),
                aesthetics.results.firstObject ? aesthetics.results.firstObject.overallScore : 0.f
            };
        }

        std::expected<Media, Error> analyzeImage(NSData *bytes) {
            CF<CGImageRef> full = decodeFull(bytes);
            if (!full) return std::unexpected("cannot decode the image");
            const std::size_t cols = CGImageGetWidth(full.get()), rows = CGImageGetHeight(full.get());
            const Bitmap      pixels = render(full.get(), cols, rows);
            const Bitmap      work = working(full.get());
            auto              d = describeFrame(work);
            if (!d) return std::unexpected(d.error());

            Media m;
            m.type = MediaType::Image;
            m.width = std::uint32_t(cols);
            m.height = std::uint32_t(rows);
            m.pixelHash = sha256(pixels.px.data(), pixels.px.size());
            m.frames.push_back(d->frame);
            m.quality = {
                .megapixels = float(cols * rows) / 1e6f,
                .bitsPerPixel = float(bytes.length * 8) / float(cols * rows),
                .sharpness = sharpness(work.view()),
                .clipped = clipped(work.view()),
                .aesthetics = d->aesthetics
            };
            return m;
        }

        void wait(dispatch_semaphore_t s) { dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER); }

        std::expected<Media, Error> analyzeVideo(NSURL *url, std::uintmax_t bytes) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@ {
            AVURLAssetPreferPreciseDurationAndTimingKey : @ YES
            }];
            dispatch_semaphore_t            done = dispatch_semaphore_create(0);
            __block NSArray<AVAssetTrack *>*tracks = nil;
            [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack*>* t, NSError*) {
                tracks = t;
                dispatch_semaphore_signal(done);
                }];
            wait(done);
            if (tracks.count == 0) return std::unexpected("video has no picture track");
            AVAssetTrack *track = tracks.firstObject;
            [track loadValuesAsynchronouslyForKeys:@ [ @ "naturalSize", @ "preferredTransform" ] completionHandler:^{
                dispatch_semaphore_signal(done); }];
            wait(done);
            [asset loadValuesAsynchronouslyForKeys:@ [ @ "duration" ] completionHandler:^{ dispatch_semaphore_signal(
                done); }];
            wait(done);
            const CGSize size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
            const double seconds = CMTimeGetSeconds(asset.duration);
            if (!(seconds > 0)) return std::unexpected("video has no duration");

            Media m;
            m.type = MediaType::Video;
            m.width = std::uint32_t(std::lround(std::abs(size.width)));
            m.height = std::uint32_t(std::lround(std::abs(size.height)));
            m.seconds = seconds;

            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(kWorkingSize, kWorkingSize);
            generator.requestedTimeToleranceBefore = kCMTimeZero;
            generator.requestedTimeToleranceAfter = kCMTimeZero;
            std::vector<Bitmap> frames;
            for (double t = kFrameStep / 2; t < seconds && frames.size() < kMaxFrames; t += kFrameStep) {
                __block CGImageRef got = nullptr;
                [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(t, 600)
                    completionHandler:^(CGImageRef img, CMTime, NSError*) {
                    if (img) got = CGImageRetain(img);
                    dispatch_semaphore_signal(done);
                    }];
                wait(done);
                CF<CGImageRef> frame{got};
                if (!frame) {
                    spdlog::warn("Cannot read frame at {:.1f} s: {}", t, url.lastPathComponent.UTF8String);
                    continue;
                }
                frames.push_back(render(frame.get(), CGImageGetWidth(frame.get()), CGImageGetHeight(frame.get())));
            }
            if (frames.empty()) return std::unexpected("no readable frames");

            std::vector<std::expected<Described, Error> > described(frames.size());
            auto *                                        out = described.data();
            const auto *                                  in = frames.data();
            dispatch_apply(frames.size(), DISPATCH_APPLY_AUTO, ^(std::size_t i)
            {
                @ autoreleasepool{
                    out[i] = describeFrame(in[i]);




                }
            });
            float sharp = 0, clip = 0, beauty = 0;
            for (std::size_t i = 0; i < frames.size(); ++i) {
                if (!described[i]) return std::unexpected(described[i].error());
                m.frames.push_back(described[i]->frame);
                sharp += sharpness(frames[i].view());
                clip += clipped(frames[i].view());
                beauty += described[i]->aesthetics;
            }
            const auto n = float(m.frames.size());
            m.quality = {
                .megapixels = float(m.width * m.height) / 1e6f,
                .bitsPerPixel = float(double(bytes) * 8 / (double(m.width) * m.height * seconds)), // per second
                .sharpness = sharp / n,
                .clipped = clip / n,
                .aesthetics = beauty / n
            };
            return m;
        }

        std::expected<Media, Error> analyzeFile(const std::filesystem::path &path) {
            NSURL *    url = [NSURL fileURLWithPath:@(path.c_str())];
            UTType *   type = [UTType typeWithFilenameExtension:url.pathExtension];
            const bool isImage = [type conformsToType:UTTypeImage], isVideo = [type conformsToType:UTTypeMovie];
            if (!isImage && !isVideo) return std::unexpected("not an image or a video");

            const auto stamp = stampOf(path);
            if (!stamp) return std::unexpected(stamp.error());
            NSError *error = nil;
            NSData * bytes = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
            if (bytes == nil) return std::unexpected(Error{error.localizedDescription.UTF8String});

            auto media = isImage ? analyzeImage(bytes) : analyzeVideo(url, bytes.length);
            if (media) {
                media->path = path;
                media->stamp = *stamp;
                media->fileHash = sha256(bytes.bytes, bytes.length);
            }
            return media;
        }

        float fullPsnr(const std::filesystem::path &a, const std::filesystem::path &b) {
            NSData *da = [NSData dataWithContentsOfFile:@(a.c_str()) options:NSDataReadingMappedIfSafe error:nil];
            NSData *db = [NSData dataWithContentsOfFile:@(b.c_str()) options:NSDataReadingMappedIfSafe error:nil];
            CF<CGImageRef> ia = da ? decodeFull(da) : nullptr, ib = db ? decodeFull(db) : nullptr;
            if (!ia || !ib) {
                spdlog::warn("Cannot re-read {} or {} for the pixel check", a.filename().string(),
                             b.filename().string());
                return std::numeric_limits<float>::quiet_NaN();
            }
            const auto pa = render(ia.get(), CGImageGetWidth(ia.get()), CGImageGetHeight(ia.get()));
            const auto pb = render(ib.get(), CGImageGetWidth(ib.get()), CGImageGetHeight(ib.get()));
            return psnr(pa.view(), pb.view());
        }
    } // namespace

    std::vector<std::filesystem::path> list(const std::filesystem::path &folder) {
        std::vector<std::filesystem::path> files;
        for (const auto &e: std::filesystem::directory_iterator(folder))
            if (e.is_regular_file() && !e.path().filename().string().starts_with('.')) files.push_back(e.path());
        std::ranges::sort(files);
        return files;
    }

    Scan analyze(std::span<const std::filesystem::path> files, const std::stop_token& stop,
                 const std::function<void(std::size_t, bool)>& onFile) {
        const auto start = std::chrono::steady_clock::now();
        spdlog::info("Examine {} files", files.size());

        std::vector<std::expected<Media, Error> > results(files.size());
        auto *                                    out = results.data();
        const auto *                              in = files.data();
        dispatch_apply(files.size(), DISPATCH_APPLY_AUTO, ^(std::size_t i)
        {
            @ autoreleasepool{
                if (stop.stop_requested())return;
                if (onFile) onFile(i, false);
                out[i] = analyzeFile(in[i]);
                if (onFile) onFile(i, true);


            }
        });
        if (stop.stop_requested()) {
            spdlog::info("Examination stopped");
            return {};
        }

        Scan scan;
        for (std::size_t i = 0; i < files.size(); ++i) {
            if (results[i]) {
                results[i]->id = MediaId{std::uint32_t(scan.media.size())};
                scan.media.push_back(std::move(*results[i]));
            } else {
                spdlog::warn("Not examined: {} ({})", files[i].filename().string(), results[i].error());
                scan.skipped.push_back({files[i], results[i].error()});
            }
        }

        std::vector<std::pair<std::uint32_t, std::uint32_t> > candidates;
        const auto &                                          media = scan.media;
        for (std::uint32_t i = 0; i < media.size(); ++i)
            for (std::uint32_t j = i + 1; j < media.size(); ++j)
                if (media[i].type == MediaType::Image && media[j].type == MediaType::Image && media[i].width == media[j]
                    .width &&
                    media[i].height == media[j].height &&
                    distance(media[i].frames[0].print, media[j].frames[0].print) < thresholds::kExactCandidatePrint)
                    candidates.emplace_back(i, j);
        std::vector<float> values(candidates.size());
        auto *             value = values.data();
        const auto *       pair = candidates.data();
        const auto *       m = media.data();
        dispatch_apply(candidates.size(), DISPATCH_APPLY_AUTO, ^(std::size_t k)
        {
            @ autoreleasepool{
                value[k] = fullPsnr(m[pair[k].first].path, m[pair[k].second].path);




            }
        });
        for (std::size_t k = 0; k < candidates.size(); ++k) scan.psnr.emplace(candidates[k], values[k]);

        spdlog::info("Examined {} files ({} skipped, {} pixel checks) in {:.1f} s", scan.media.size(),
                     scan.skipped.size(),
                     candidates.size(),
                     std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count());
        return scan;
    }

    std::expected<Picture, std::string> thumbnail(const std::filesystem::path &path, std::size_t side) {
        @ autoreleasepool{
            NSURL * url = [NSURL fileURLWithPath:@(path.c_str())];
            CF<CGImageRef > img;
            if ([[UTType typeWithFilenameExtension:url.pathExtension] conformsToType:UTTypeMovie]) {
                AVAssetImageGenerator * generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset
                    assetWithURL:url]];
                generator.appliesPreferredTrackTransform = YES;
                generator.maximumSize = CGSizeMake(side, side);
                dispatch_semaphore_t done = dispatch_semaphore_create(0);
                __block CGImageRef got = nullptr;
                [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(1.0, 600)
                completionHandler:^(CGImageRef frame, CMTime, NSError *) {
                                                  if (frame) got = CGImageRetain(frame);
                    dispatch_semaphore_signal(done);


                }];
                wait(done);
                img.reset(got);


            }else {
                CF<CGImageSourceRef > src{CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr)};
                NSDictionary * options = @ {
                    (id) kCGImageSourceCreateThumbnailFromImageAlways: @ YES,
                    (id) kCGImageSourceCreateThumbnailWithTransform: @ YES,
                    (id) kCGImageSourceThumbnailMaxPixelSize: @ (side),
                };
                if (src) img.reset(CGImageSourceCreateThumbnailAtIndex(src.get(), 0, (__bridge CFDictionaryRef)options)
);


            }
            if (!img)return std::unexpected("cannot read the file");
            Bitmap b = render(img.get(), CGImageGetWidth(img.get()), CGImageGetHeight(img.get()));
            return Picture{b.cols, b.rows, std::move(b.px)};


        }
    }
} // namespace clerk
