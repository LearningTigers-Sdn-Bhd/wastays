# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelKnowledges::RecoverStaleIndexing do
  include ActiveJob::TestHelper

  subject(:recover) { described_class.new(now: now) }

  let(:now) { Time.zone.parse("2026-09-28 10:00:00") }
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  def indexing_document(updated_at:, metadata: {})
    document = create(:hotel_knowledge_document, hotel: hotel, content: "Hotel information")
    clear_enqueued_jobs
    document.update_columns(embedding_status: "indexing", metadata: metadata, updated_at: updated_at)
    document.reload
  end

  it "ignores fresh indexing documents" do
    document = indexing_document(updated_at: now - 29.minutes)

    result = recover.call

    expect(result).to have_attributes(retried: 0, failed: 0)
    expect(document.reload.embedding_status).to eq("indexing")
    expect(enqueued_jobs).to be_empty
  end

  it "records and enqueues the first stale recovery" do
    document = indexing_document(updated_at: now - 31.minutes)

    expect { recover.call }
      .to have_enqueued_job(HotelKnowledges::GenerateEmbeddingsJob)
      .with(document.id, recovery_attempt: 1).once

    expect(document.reload).to have_attributes(embedding_status: "indexing")
    expect(document.metadata).to include(
      "indexing_recovery_attempts" => 1,
      "indexing_recovered_at" => now.iso8601
    )
  end

  it "marks the second stale cycle failed without enqueuing again" do
    document = indexing_document(
      updated_at: now - 31.minutes,
      metadata: {
        "indexing_recovery_attempts" => 1,
        "indexing_recovered_at" => 1.hour.ago.iso8601
      }
    )

    result = recover.call

    expect(result).to have_attributes(retried: 0, failed: 1)
    expect(document.reload.embedding_status).to eq("failed")
    expect(document.metadata["last_error"]).to eq(described_class::TIMEOUT_ERROR)
    expect(enqueued_jobs).to be_empty
  end

  it "ignores stale documents for hotels with AI disabled" do
    hotel.update!(ai_provider_enabled: false, ai_provider_key: nil, ai_provider_name: nil)
    document = indexing_document(updated_at: now - 31.minutes)

    result = recover.call

    expect(result).to have_attributes(retried: 0, failed: 0)
    expect(document.reload.embedding_status).to eq("indexing")
    expect(enqueued_jobs).to be_empty
  end

  it "does not enqueue a second recovery when another sweep sees the same document" do
    document = indexing_document(updated_at: now - 31.minutes)

    recover.call
    described_class.new(now: now).call

    expect(enqueued_jobs.count { |job| job[:job] == HotelKnowledges::GenerateEmbeddingsJob }).to eq(1)
    expect(document.reload.metadata["indexing_recovery_attempts"]).to eq(1)
  end
end
