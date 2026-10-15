<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Settings registry
    |--------------------------------------------------------------------------
    |
    | The single source of truth for every configurable platform setting. Each
    | entry describes the setting's presentation metadata (group, label,
    | description), how a submitted value must be validated (type, required,
    | bounds), and the default used when the setting has no stored value or the
    | stored value is missing or malformed.
    |
    | The key is the `settings.key` value. Adding a setting here and to the
    | seeder is all that is required — no schema change, because the `settings`
    | table stores rows, not columns.
    |
    | Types:
    |   - string  : free text, bounded by `max_length`
    |   - text    : longer free text, bounded by `max_length`
    |   - email   : a valid email address
    |   - integer : a whole number within `min`/`max`
    |   - decimal : a number within `min`/`max`
    |
    | Values are stored as text in the database; `default` mirrors that.
    |
    */

    'keys' => [

        'system.name' => [
            'group' => 'system',
            'label' => 'System Name',
            'description' => 'The display name of the platform.',
            'type' => 'string',
            'required' => true,
            'max_length' => 255,
            'default' => 'AgroBenta',
        ],

        'system.description' => [
            'group' => 'system',
            'label' => 'System Description',
            'description' => 'A brief description of the platform.',
            'type' => 'text',
            'required' => false,
            'max_length' => 1000,
            'default' => 'A livestock trading platform connecting buyers and sellers.',
        ],

        'admin_contact.name' => [
            'group' => 'admin_contact',
            'label' => 'Contact Name',
            'description' => 'Name displayed as the platform contact.',
            'type' => 'string',
            'required' => false,
            'max_length' => 255,
            'default' => 'Administrator',
        ],

        'admin_contact.email' => [
            'group' => 'admin_contact',
            'label' => 'Contact Email',
            'description' => 'Email address for platform inquiries.',
            'type' => 'email',
            'required' => false,
            'max_length' => 255,
            'default' => 'admin@agrobenta.example.com',
        ],

        'admin_contact.phone' => [
            'group' => 'admin_contact',
            'label' => 'Contact Phone',
            'description' => 'Phone number for platform inquiries.',
            'type' => 'string',
            'required' => false,
            'max_length' => 50,
            'default' => '',
        ],

        'listing.max_photos' => [
            'group' => 'listings',
            'label' => 'Maximum Photos per Listing',
            'description' => 'The most photos a single listing may hold.',
            'type' => 'integer',
            'required' => false,
            'min' => 1,
            'max' => 50,
            'default' => '10',
        ],

        'listing.max_price' => [
            'group' => 'listings',
            'label' => 'Maximum Asking Price',
            'description' => 'The highest asking price a listing may be given.',
            'type' => 'decimal',
            'required' => false,
            'min' => 0.01,
            'max' => 99999999999.99,
            'default' => '99999999999.99',
        ],

        'verification.guidance' => [
            'group' => 'verification',
            'label' => 'Verification Guidance',
            'description' => 'Guidance shown to sellers when submitting verification.',
            'type' => 'text',
            'required' => false,
            'max_length' => 2000,
            'default' => '',
        ],

    ],

];
