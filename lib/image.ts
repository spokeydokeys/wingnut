/**
 * Shrinking a phone photo before it leaves the phone.
 *
 * SPEC.md 4.7 asks for 1600px. The reason is not storage -- it is that the
 * upload happens at a fuel dock on one bar of signal, and a 4 MB original is
 * the difference between a receipt that is filed and one that is still in a
 * pocket a month later. At 1600px a receipt is still readable enough to check
 * a total against, which is the only thing anybody ever does with the image.
 *
 * Browser-only: it draws on a canvas. Imported by the capture form, which is a
 * client component, and by nothing on the server.
 */

/** What comes out, whatever went in. One format keeps the object keys simple. */
const OUTPUT_TYPE = "image/jpeg";

/**
 * Quality 0.82: the point where a photographed receipt stops getting visibly
 * worse and starts getting bigger for nothing.
 */
const OUTPUT_QUALITY = 0.82;

/**
 * A smaller version of the picture, or the original if anything goes wrong.
 *
 * Falling back to the original rather than throwing is deliberate. The worst
 * case of a failed resize is a slow upload; the worst case of a thrown error
 * is a pilot who cannot file a receipt at all because their browser did not
 * like something about a canvas.
 */
export async function shrinkImage(file: File, maxEdge = 1600): Promise<Blob> {
  try {
    // `from-image` applies the EXIF rotation. Without it a photo taken in
    // portrait arrives on its side, which is how every receipt scanner that
    // skipped this step is remembered.
    const source = await createImageBitmap(file, { imageOrientation: "from-image" });

    const scale = Math.min(1, maxEdge / Math.max(source.width, source.height));
    if (scale === 1 && file.type === OUTPUT_TYPE) {
      source.close();
      return file;
    }

    const canvas = document.createElement("canvas");
    canvas.width = Math.round(source.width * scale);
    canvas.height = Math.round(source.height * scale);

    const context = canvas.getContext("2d");
    if (!context) return file;
    context.drawImage(source, 0, 0, canvas.width, canvas.height);
    source.close();

    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, OUTPUT_TYPE, OUTPUT_QUALITY),
    );
    return blob ?? file;
  } catch {
    return file;
  }
}
