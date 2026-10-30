// Standalone, read-only API experiment. Not linked into Photo or SwiftPM.
#include <libraw/libraw.h>
#include <chrono>
#include <cstdlib>
#include <cerrno>
#include <fcntl.h>
#include <unistd.h>
#include <iostream>
#include <string>
#include <sys/resource.h>

using Clock = std::chrono::steady_clock;
static double ms(Clock::time_point start) {
  return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}
static int cancel(void *, enum LibRaw_progress, int, int) { return 1; }
static void quiet(void *, const char *, const INT64) {}
int main(int argc, char **argv) {
  if (argc != 3 && argc != 4) return 2; // mode: preview, full, cancel; then input file
  LibRaw raw;
  raw.set_dataerror_handler(quiet, nullptr);
  const std::string mode(argv[1]);
  if (mode != "preview" && mode != "full" && mode != "cancel") return 2;
  auto start = Clock::now();
  int opened = raw.open_file(argv[2]);
  const double metadata = ms(start);
  const auto width = raw.imgdata.sizes.width, height = raw.imgdata.sizes.height;
  const auto flip = raw.imgdata.sizes.flip;
  const bool hasISO = raw.imgdata.other.iso_speed > 0;
  const bool hasShutter = raw.imgdata.other.shutter > 0;
  const bool hasAperture = raw.imgdata.other.aperture > 0;
  const bool hasFocal = raw.imgdata.other.focal_len > 0;
  int thumbError = opened, thumbWidth = 0, thumbHeight = 0, thumbBytes = 0, thumbType = 0;
  double thumbnail = 0, thumbnailWrite = 0, unpack = 0, render = 0;
  bool exported = false;
  int unpackError = opened, renderError = opened, outputWidth = 0, outputHeight = 0;
  if (!opened) {
    start = Clock::now();
    thumbError = raw.unpack_thumb();
    if (!thumbError) {
      auto *thumb = raw.dcraw_make_mem_thumb(&thumbError);
      if (thumb) {
        thumbWidth = raw.imgdata.thumbnail.twidth; thumbHeight = raw.imgdata.thumbnail.theight;
        thumbBytes = thumb->data_size; thumbType = thumb->type;
        if (!thumbnail) thumbnail = ms(start);
        if (argc == 4 && thumb->type == LIBRAW_IMAGE_JPEG) {
          // Create a new private scratch file only; never replace an input or existing file.
          auto writeStart = Clock::now();
          int fd = open(argv[3], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
          if (fd < 0) { LibRaw::dcraw_clear_mem(thumb); return 3; }
          size_t done = 0;
          while (done < thumb->data_size) {
            ssize_t count = write(fd, thumb->data + done, thumb->data_size - done);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) { close(fd); unlink(argv[3]); LibRaw::dcraw_clear_mem(thumb); return 3; }
            done += static_cast<size_t>(count);
          }
          if (close(fd) != 0) { unlink(argv[3]); LibRaw::dcraw_clear_mem(thumb); return 3; }
          exported = true;
          thumbnailWrite = ms(writeStart);
        }
        LibRaw::dcraw_clear_mem(thumb);
      }
    }
    if (!thumbnail) thumbnail = ms(start);
    if (mode == "full" || mode == "cancel") {
      if (mode == "cancel") raw.set_progress_handler(cancel, nullptr);
      start = Clock::now();
      unpackError = raw.unpack();
      unpack = ms(start);
      if (!unpackError && mode == "full") {
        raw.imgdata.params.use_camera_wb = 1;
        raw.imgdata.params.output_color = 1; // sRGB, 8-bit, defaults otherwise
        raw.imgdata.params.output_bps = 8;
        start = Clock::now();
        renderError = raw.dcraw_process();
        if (!renderError) {
          auto *image = raw.dcraw_make_mem_image(&renderError);
          if (image) {
            outputWidth = image->width; outputHeight = image->height;
            LibRaw::dcraw_clear_mem(image);
          }
        }
        render = ms(start);
      }
    }
  }
  rusage usage{};
  getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
  const double rss = usage.ru_maxrss / 1048576.0;
#else
  const double rss = usage.ru_maxrss / 1024.0;
#endif
  std::cout << "{\"version\":\"" << LibRaw::version()
    << "\",\"mode\":\"" << mode << "\",\"openError\":" << opened
    << ",\"metadataMilliseconds\":" << metadata
    << ",\"sensorWidth\":" << width << ",\"sensorHeight\":" << height
    << ",\"orientationFlip\":" << flip << ",\"hasISO\":" << hasISO
    << ",\"hasShutter\":" << hasShutter << ",\"hasAperture\":" << hasAperture
    << ",\"hasFocalLength\":" << hasFocal << ",\"thumbnailError\":" << thumbError
    << ",\"thumbnailExtractionMilliseconds\":" << thumbnail
    << ",\"thumbnailExported\":" << exported << ",\"thumbnailWriteMilliseconds\":" << thumbnailWrite
    << ",\"thumbnailWidth\":" << thumbWidth << ",\"thumbnailHeight\":" << thumbHeight
    << ",\"thumbnailBytes\":" << thumbBytes << ",\"thumbnailType\":" << thumbType
    << ",\"unpackError\":" << unpackError << ",\"unpackMilliseconds\":" << unpack
    << ",\"renderError\":" << renderError << ",\"renderMilliseconds\":" << render
    << ",\"renderedWidth\":" << outputWidth << ",\"renderedHeight\":" << outputHeight
    << ",\"cancelledByCallback\":" << (unpackError == LIBRAW_CANCELLED_BY_CALLBACK)
    << ",\"peakResidentMiB\":" << rss << "}\n";
  return opened ? 1 : 0;
}
