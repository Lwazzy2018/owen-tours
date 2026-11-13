using ImageMagick;
using OwenTours.Application.Abstractions;
using OwenTours.Domain.Rules;

namespace OwenTours.Infrastructure.Images;

/// <summary>
/// Resizes uploads to a full-size image (max 1600 px) and a thumbnail (max 480 px), saved as JPEG.
/// Strip() removes EXIF data such as GPS location, which matters for student ID photos.
/// Uses Magick.NET (Apache 2.0 licence). Also reads iPhone HEIC photos.
/// </summary>
public sealed class MagickImageProcessor : IImageProcessor
{
    private const uint FullSize = 1600;
    private const uint ThumbSize = 480;
    private const uint JpegQuality = 82;

    public async Task<ProcessedImage> ProcessAsync(Stream input, CancellationToken ct)
    {
        // Copy to memory first: upload streams can't always seek.
        using var buffer = new MemoryStream();
        await input.CopyToAsync(buffer, ct);
        buffer.Position = 0;

        MagickImage image;
        try
        {
            image = new MagickImage(buffer);
        }
        catch (MagickException)
        {
            throw new BusinessRuleException("That file isn't a photo we can read. Please upload a JPG, PNG, WEBP or HEIC image.", 415);
        }

        using (image)
        {
            image.AutoOrient();   // turn sideways phone photos the right way up
            image.Strip();        // remove EXIF/GPS and other metadata
            return new ProcessedImage(Encode(image, FullSize), Encode(image, ThumbSize), "image/jpeg", ".jpg");
        }
    }

    private static byte[] Encode(MagickImage source, uint maxSize)
    {
        using var copy = source.Clone();
        copy.Resize(new MagickGeometry(maxSize, maxSize) { Greater = true }); // only shrink, never enlarge
        copy.Quality = JpegQuality;
        return copy.ToByteArray(MagickFormat.Jpeg);
    }
}