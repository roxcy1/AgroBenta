<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('user_reports', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('reporter_id')->constrained('users');
            $table->foreignId('reported_user_id')->constrained('users');
            $table->enum('reason', [
                'scam_fraud',
                'harassment',
                'misleading_information',
                'spam_suspicious_activity',
                'inappropriate_content',
                'other',
            ]);
            $table->text('description');
            $table->string('evidence_path')->nullable();
            $table->enum('status', ['pending', 'dismissed', 'actioned'])
                ->default('pending');
            $table->foreignId('reviewed_by')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->text('admin_note')->nullable();
            $table->timestamps();

            $table->index(['reporter_id']);
            $table->index(['reported_user_id']);
            $table->index(['status']);
            $table->index(['created_at']);
            $table->index(['reporter_id', 'reported_user_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_reports');
    }
};
