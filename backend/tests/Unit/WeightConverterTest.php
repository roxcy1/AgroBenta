<?php

namespace Tests\Unit;

use App\Support\WeightConverter;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

class WeightConverterTest extends TestCase
{
    public function test_kilograms_pass_through_unchanged(): void
    {
        $this->assertSame(500.0, WeightConverter::toKilograms(500, 'kg'));
        $this->assertSame(320.5, WeightConverter::toKilograms('320.50', 'kg'));
    }

    public function test_pounds_use_the_canonical_factor(): void
    {
        $this->assertEqualsWithDelta(
            498.951607,
            WeightConverter::toKilograms(1100, 'lb'),
            0.0000001,
        );
        $this->assertEqualsWithDelta(
            499.9994053747,
            WeightConverter::toKilograms(1102.31, 'lb'),
            0.0000001,
        );
    }

    public function test_unknown_unit_is_rejected(): void
    {
        $this->expectException(InvalidArgumentException::class);

        WeightConverter::toKilograms(10, 'stone');
    }
}
