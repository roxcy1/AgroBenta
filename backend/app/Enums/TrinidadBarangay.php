<?php

namespace App\Enums;

/** The approved barangays for AgroBenta's initial Trinidad, Bohol locale. */
enum TrinidadBarangay: string
{
    case Banlasan = 'Banlasan';
    case Bongbong = 'Bongbong';
    case Catoogan = 'Catoogan';
    case Guinobatan = 'Guinobatan';
    case HinlayaganIlaud = 'Hinlayagan Ilaud';
    case HinlayaganIlaya = 'Hinlayagan Ilaya';
    case Kauswagan = 'Kauswagan';
    case KinanOan = 'Kinan-oan';
    case LaUnion = 'La Union';
    case LaVictoria = 'La Victoria';
    case MabuhayCabigohan = 'Mabuhay Cabigohan';
    case Mahagbu = 'Mahagbu';
    case ManuelMRoxas = 'Manuel M. Roxas';
    case Poblacion = 'Poblacion';
    case SanIsidro = 'San Isidro';
    case SanVicente = 'San Vicente';
    case SantoTomas = 'Santo Tomas';
    case Soom = 'Soom';
    case TagumNorte = 'Tagum Norte';
    case TagumSur = 'Tagum Sur';

    /**
     * The public catalog is name-only. No PSGC codes are present in this
     * project, so none are fabricated here.
     *
     * @return list<string>
     */
    public static function names(): array
    {
        return array_map(
            static fn (self $barangay): string => $barangay->value,
            self::cases(),
        );
    }

    public static function contains(string $name): bool
    {
        return self::tryFrom(trim($name)) !== null;
    }
}
