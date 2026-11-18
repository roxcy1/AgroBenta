<?php

namespace App\Services\UserReport;

use App\Models\UserReport;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Private storage for optional report screenshots.
 *
 * Paths are disk-relative and are never exposed as URLs. A client filename is
 * never used as a path segment; the stored name is server-generated.
 */
class UserReportEvidenceService
{
    public const string DISK = 'user-report-evidence';

    public function store(UploadedFile $file): string
    {
        $extension = $file->guessExtension() ?? 'bin';
        $name = Str::random(40).'.'.$extension;
        $path = $file->storeAs('reports', $name, self::DISK);

        if (! is_string($path)) {
            abort(500, 'The report evidence could not be stored.');
        }

        return $path;
    }

    public function delete(?string $path): void
    {
        if ($path !== null && $path !== '') {
            Storage::disk(self::DISK)->delete($path);
        }
    }

    public function exists(?string $path): bool
    {
        return $path !== null && $path !== ''
            && Storage::disk(self::DISK)->exists($path);
    }

    /**
     * Stream one report screenshot with private, non-cacheable headers.
     */
    public function response(UserReport $report): StreamedResponse
    {
        $disk = Storage::disk(self::DISK);
        $path = $report->evidence_path;

        abort_if($path === null || $path === '' || ! $disk->exists($path), 404);

        $extension = pathinfo($path, PATHINFO_EXTENSION);
        $filename = "agrobenta-report-{$report->getKey()}"
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
}
