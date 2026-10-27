<?php

namespace App\Services\SellerVerification;

use App\Enums\SellerVerificationDocumentType;
use App\Models\SellerVerification;
use App\Models\User;
use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Private storage for seller verification documents.
 *
 * ## Why the paths, not the files, live in the database
 *
 * `seller_verifications.id_document_path` and `selfie_path` hold disk-relative
 * paths on the private `seller-verification-documents` disk. The columns never
 * hold a URL: a URL is a capability, and a stored one would outlive every check
 * this class performs. Documents are served only through authenticated,
 * owner-or-administrator streaming endpoints.
 *
 * ## Staging
 *
 * A seller uploads before they submit, so the review step can show that both
 * files are actually persisted. Uploads therefore go to `staging/{userId}/`
 * first and are promoted to `verifications/{verificationId}/` inside the
 * submission transaction. A staged file belongs to exactly one account, is
 * replaced rather than appended, and is deleted after promotion.
 *
 * Nothing here trusts a client-supplied path: the only path segments are the
 * authenticated user's id and the server-generated verification id, and the
 * filename is the enum value plus an extension the validator already allowed.
 */
class SellerVerificationDocumentService
{
    /**
     * The private disk. Named in one place so a deployment can move it to S3
     * by configuration without touching the code.
     */
    public const string DISK = 'seller-verification-documents';

    /**
     * Store (or replace) one staged document for [user].
     *
     * Returns the disk-relative path. A previous staged file of the same type
     * is removed first, so a replacement cannot leave the old file behind for
     * an administrator to find later.
     */
    public function stage(
        User $user,
        SellerVerificationDocumentType $type,
        UploadedFile $file,
    ): string {
        $directory = $this->stagingDirectory($user);
        $this->deleteMatching($directory, $type);

        $extension = $this->extensionFor($file);
        $path = "{$directory}/{$type->value}.{$extension}";

        // `storeAs` uses the server-generated path, never the client filename.
        Storage::disk(self::DISK)->putFileAs(
            $directory,
            $file,
            "{$type->value}.{$extension}",
        );

        return $path;
    }

    /**
     * Remove a staged document. Returns false when there was nothing to remove,
     * which the controller turns into a 404 rather than a success.
     */
    public function forgetStaged(User $user, SellerVerificationDocumentType $type): bool
    {
        return $this->deleteMatching($this->stagingDirectory($user), $type);
    }

    /**
     * Whether a staged document of [type] exists for [user].
     */
    public function hasStaged(User $user, SellerVerificationDocumentType $type): bool
    {
        return $this->stagedPath($user, $type) !== null;
    }

    /**
     * The staged path of [type], or null when the seller has not uploaded it.
     */
    public function stagedPath(
        User $user,
        SellerVerificationDocumentType $type,
    ): ?string {
        return $this->findByType($this->stagingDirectory($user), $type);
    }

    /**
     * The document types [user] has not staged yet.
     *
     * Used by the submission controller to answer 422 with per-field errors
     * instead of creating a record whose documents are missing.
     *
     * @return list<SellerVerificationDocumentType>
     */
    public function missingStaged(User $user): array
    {
        return array_values(array_filter(
            SellerVerificationDocumentType::cases(),
            fn (SellerVerificationDocumentType $type): bool => ! $this->hasStaged($user, $type),
        ));
    }

    /**
     * Move every staged file onto the new verification record.
     *
     * Runs inside the submission transaction. The caller persists the returned
     * `column => path` map; this method only touches the filesystem. Promotion
     * is a move, not a copy: after it succeeds the staging directory is empty,
     * so a rejected-and-resubmitted application cannot inherit documents from
     * the previous attempt.
     *
     * @return array<string, string>
     *
     * @throws \RuntimeException when a staged file vanished between the
     *                           controller's pre-check and the move.
     */
    public function promote(User $user, SellerVerification $verification): array
    {
        $paths = [];
        $destination = "verifications/{$verification->getKey()}";

        foreach (SellerVerificationDocumentType::cases() as $type) {
            $staged = $this->stagedPath($user, $type);

            if ($staged === null) {
                throw new \RuntimeException(
                    "Missing staged {$type->value} document.",
                );
            }

            $filename = basename($staged);
            $target = "{$destination}/{$filename}";

            $this->disk()->move($staged, $target);
            $paths[$type->column()] = $target;
        }

        // The staging directory should now be empty. Remove it so a future
        // application starts from a clean slate.
        $this->disk()->deleteDirectory($this->stagingDirectory($user));

        return $paths;
    }

    /**
     * Remove files promoted for a submission that did not commit.
     *
     * The database transaction owns the record, but the filesystem move is not
     * transactional. If anything after `promote()` fails, the record is rolled
     * back and this removes the directory that would otherwise become an orphan.
     * It must never be called for a committed verification.
     */
    public function discardPromoted(SellerVerification $verification): void
    {
        $this->disk()->deleteDirectory("verifications/{$verification->getKey()}");
    }

    /**
     * The stored path for one document, or null for a legacy record that never
     * had files.
     */
    public function pathFor(
        SellerVerification $verification,
        SellerVerificationDocumentType $type,
    ): ?string {
        $path = $verification->getAttribute($type->column());

        return is_string($path) && $path !== '' ? $path : null;
    }

    /**
     * A private, non-cacheable inline response for one stored document.
     *
     * Streams from the disks' own path so the file is never handed to the web
     * server as a public asset. `Cache-Control: private, no-store` keeps a
     * shared cache or proxy from retaining a government ID, and `nosniff`
     * stops a browser from reinterpreting the bytes.
     */
    public function response(
        SellerVerification $verification,
        SellerVerificationDocumentType $type,
    ): StreamedResponse {
        $path = $this->pathFor($verification, $type);
        $disk = $this->disk();

        abort_if($path === null || ! $disk->exists($path), 404);

        $extension = pathinfo($path, PATHINFO_EXTENSION);
        $filename = "agrobenta-{$type->value}-{$verification->getKey()}"
            .($extension !== '' ? ".{$extension}" : '');

        return response()->streamDownload(
            function () use ($disk, $path): void {
                $stream = $disk->readStream($path);

                if ($stream === null) {
                    return;
                }

                fpassthru($stream);
                fclose($stream);
            },
            $filename,
            [
                'Content-Type' => $disk->mimeType($path) ?: 'application/octet-stream',
                'Cache-Control' => 'private, no-store, max-age=0',
                'X-Content-Type-Options' => 'nosniff',
            ],
            'inline',
        );
    }

    /**
     * Delete the one staged file of [type], if any.
     */
    private function deleteMatching(
        string $directory,
        SellerVerificationDocumentType $type,
    ): bool {
        $paths = array_filter(
            $this->disk()->files($directory),
            fn (string $path): bool => $this->belongsToType($path, $type),
        );

        if ($paths === []) {
            return false;
        }

        $this->disk()->delete(array_values($paths));

        return true;
    }

    private function findByType(
        string $directory,
        SellerVerificationDocumentType $type,
    ): ?string {
        foreach ($this->disk()->files($directory) as $path) {
            if ($this->belongsToType($path, $type)) {
                return $path;
            }
        }

        return null;
    }

    private function belongsToType(
        string $path,
        SellerVerificationDocumentType $type,
    ): bool {
        return str_starts_with(basename($path), "{$type->value}.");
    }

    private function stagingDirectory(User $user): string
    {
        return "staging/{$user->getKey()}";
    }

    /**
     * The extension is taken from the file's sniffed MIME type, not from the
     * client's filename, so `id.pdf` that is really a JPEG is still stored as
     * a JPEG. The validator has already restricted the allowed types.
     */
    private function extensionFor(UploadedFile $file): string
    {
        $extension = strtolower((string) $file->extension());

        return in_array($extension, ['jpg', 'jpeg', 'png', 'webp'], true)
            ? $extension
            : 'png';
    }

    private function disk(): Filesystem
    {
        return Storage::disk(self::DISK);
    }
}
