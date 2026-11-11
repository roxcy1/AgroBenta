import { useState } from 'react';
import { ChevronLeft, ChevronRight, ImageOff } from 'lucide-react';
import { clampPhotoIndex, photoPosition, stepPhotoIndex } from './photoNavigation';

interface ListingPhotosProps {
  photos: string[];
  /** Names the listing in each image's description, e.g. "Listing #4". */
  label: string;
  /** Keep the full-size link in this component unless a details toolbar owns it. */
  showOpenFullSize?: boolean;
}

/**
 * The photos of one listing, shown so a moderator can see the animal before
 * deciding on it.
 *
 * One large photo with previous/next controls and a strip of thumbnails to jump
 * between them. A photo that cannot be loaded — typically because the storage
 * link is missing on the server — says so in place of a broken image, so the
 * moderator is not left wondering whether the listing has no photos at all.
 */
export default function ListingPhotos({ photos, label, showOpenFullSize = true }: ListingPhotosProps) {
  const [index, setIndex] = useState(0);
  const [failed, setFailed] = useState<ReadonlySet<string>>(new Set());

  if (photos.length === 0) {
    return <p className="lv-photos-empty">No photos uploaded</p>;
  }

  const current = clampPhotoIndex(index, photos.length);
  const url = photos[current];
  const position = photoPosition(current, photos.length);
  const canStep = photos.length > 1;

  function markFailed(failedUrl: string) {
    setFailed((previous) => new Set(previous).add(failedUrl));
  }

  return (
    <div className="lv-photos">
      <div className="lv-photos-stage">
        {failed.has(url) ? (
          <div className="lv-photos-fallback">
            <ImageOff size={28} aria-hidden="true" />
            <span>This photo could not be loaded.</span>
          </div>
        ) : (
          <img
            className="lv-photos-image"
            src={url}
            alt={`${label}: ${position}`}
            onError={() => markFailed(url)}
          />
        )}

        {canStep && (
          <>
            <button
              type="button"
              className="lv-photos-step lv-photos-step--prev"
              aria-label="Previous photo"
              onClick={() => setIndex(stepPhotoIndex(current, photos.length, -1))}
            >
              <ChevronLeft size={20} aria-hidden="true" />
            </button>
            <button
              type="button"
              className="lv-photos-step lv-photos-step--next"
              aria-label="Next photo"
              onClick={() => setIndex(stepPhotoIndex(current, photos.length, 1))}
            >
              <ChevronRight size={20} aria-hidden="true" />
            </button>
          </>
        )}
      </div>

      <div className="lv-photos-bar">
        <span className="lv-photos-position" aria-live="polite">
          {position}
        </span>
        {showOpenFullSize && (
          <a className="lv-photos-open" href={url} target="_blank" rel="noopener noreferrer">
            Open full size
          </a>
        )}
      </div>

      {canStep && (
        <ul className="lv-photos-thumbs">
          {photos.map((photoUrl, photoIndex) => (
            <li key={photoUrl}>
              <button
                type="button"
                className={`lv-photos-thumb${photoIndex === current ? ' lv-photos-thumb--active' : ''}`}
                aria-label={`Show ${photoPosition(photoIndex, photos.length).toLowerCase()}`}
                aria-current={photoIndex === current}
                onClick={() => setIndex(photoIndex)}
              >
                {failed.has(photoUrl) ? (
                  <ImageOff size={16} aria-hidden="true" />
                ) : (
                  <img src={photoUrl} alt="" loading="lazy" onError={() => markFailed(photoUrl)} />
                )}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

interface ListingPhotoThumbProps {
  /** The first photo, or undefined when the listing has none. */
  url: string | undefined;
}

/** A small first-photo preview for a listings table row. */
export function ListingPhotoThumb({ url }: ListingPhotoThumbProps) {
  const [failed, setFailed] = useState(false);

  if (!url || failed) {
    return (
      <span className="lv-row-thumb lv-row-thumb--empty" role="img" aria-label="No photo">
        <ImageOff size={16} aria-hidden="true" />
      </span>
    );
  }

  return (
    <img
      className="lv-row-thumb"
      src={url}
      alt=""
      loading="lazy"
      onError={() => setFailed(true)}
    />
  );
}
