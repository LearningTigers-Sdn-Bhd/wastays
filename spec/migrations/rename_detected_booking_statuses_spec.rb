# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260801090000_rename_detected_booking_statuses")

RSpec.describe RenameDetectedBookingStatuses do
  subject(:migration) { described_class.new }

  around do |example|
    if ActiveRecord::Base.connection.column_exists?(:bookings, :no_show_detected_business_date)
      ActiveRecord::Migration.suppress_messages { migration.down }
      Booking.reset_column_information
    end

    example.run
  ensure
    if ActiveRecord::Base.connection.column_exists?(:bookings, :no_show_review_business_date)
      ActiveRecord::Migration.suppress_messages { migration.up }
      Booking.reset_column_information
    end
  end

  it "reversibly renames persisted booking status vocabulary without changing free text" do
    hotel = create(:hotel)
    booking = create(:booking, hotel:, status: "confirmed")
    booking.update_column(:status, "review_no_show")

    booking_log = create(:booking_audit_log, hotel:, auditable: booking)
    booking_log.update_columns(
      old_value: { "status" => "confirmed" },
      new_value: { "status" => "review_no_show" },
      metadata: {
        "from" => "confirmed",
        "to" => "review_no_show",
        "event" => "review_no_show",
        "correction_reason" => "finalize_no_show_review",
        "reason" => "review_no_show"
      }
    )

    room_log = create(:room_operational_audit_log, hotel:)
    room_log.update_columns(
      old_status: "review_due_out",
      new_status: "review_no_show",
      event_type: "review_no_show_cancelled",
      metadata: {
        "booking_status" => "review_due_out",
        "event" => "detect_late_checkout",
        "note" => "detect_late_checkout"
      }
    )

    night_audit = create(:night_audit, hotel:)
    night_audit.update_columns(
      summary: {
        "review_no_show_count" => 2,
        "run_results" => {
          "status_changes" => {
            "items" => [ { "from" => "review_no_show", "to" => "review_due_out" } ]
          }
        },
        "note" => "review_no_show"
      },
      exceptions: {
        "review_no_show" => [ { "status" => "review_no_show" } ],
        "review_due_out" => [ { "status" => "review_due_out" } ]
      },
      blocked_details: {
        "legacy" => [ { "previous_status" => "review_due_out", "reason" => "review_due_out" } ]
      }
    )
    night_log = NightAuditLog.create!(
      night_audit:,
      hotel:,
      action_type: "process_started",
      metadata: {
        "reviewed_no_show_count" => 2,
        "reviewed_due_out_count" => 1,
        "type" => "review_due_out",
        "items" => [ {
          "item_key" => "due_out_review:#{booking.id}:2026-08-01",
          "item_type" => "due_out_review",
          "event" => "detect_late_checkout"
        } ]
      }
    )
    folio_transaction = create(
      :folio_transaction,
      correction_reason: "finalize_no_show_review",
      metadata: { "override_reason" => "finalize_no_show_review" }
    )
    financial_event = create(
      :financial_audit_event,
      reason: "finalize_no_show_review",
      metadata: { "correction_reason" => "finalize_no_show_review" }
    )

    ActiveRecord::Migration.suppress_messages { migration.up }
    Booking.reset_column_information

    expect(booking.reload.status).to eq("no_show_detected")
    expect(booking_log.reload.new_value).to eq("status" => "no_show_detected")
    expect(booking_log.metadata).to include(
      "to" => "no_show_detected",
      "event" => "detect_no_show",
      "correction_reason" => "finalize_no_show_detection",
      "reason" => "review_no_show"
    )
    expect(room_log.reload.attributes).to include(
      "old_status" => "due_out_detected",
      "new_status" => "no_show_detected",
      "event_type" => "no_show_detection_cancelled"
    )
    expect(room_log.metadata).to include(
      "booking_status" => "due_out_detected",
      "event" => "detect_due_out",
      "note" => "detect_late_checkout"
    )
    expect(night_audit.reload.summary).to include(
      "no_show_detected_count" => 2,
      "note" => "review_no_show"
    )
    expect(night_audit.summary.dig("run_results", "status_changes", "items", 0)).to eq(
      "from" => "no_show_detected",
      "to" => "due_out_detected"
    )
    expect(night_audit.exceptions.keys).to contain_exactly("no_show_detected", "due_out_detected")
    expect(night_audit.blocked_details.dig("legacy", 0)).to eq(
      "previous_status" => "due_out_detected",
      "reason" => "review_due_out"
    )
    expect(night_log.reload.metadata).to include(
      "no_show_detected_count" => 2,
      "due_out_detected_count" => 1,
      "type" => "due_out_detected"
    )
    expect(night_log.metadata.dig("items", 0)).to include(
      "item_key" => "due_out_detection:#{booking.id}:2026-08-01",
      "item_type" => "due_out_detection",
      "event" => "detect_due_out"
    )
    expect(folio_transaction.reload).to have_attributes(correction_reason: "finalize_no_show_detection")
    expect(folio_transaction.metadata["override_reason"]).to eq("finalize_no_show_detection")
    expect(financial_event.reload).to have_attributes(reason: "finalize_no_show_detection")
    expect(financial_event.metadata["correction_reason"]).to eq("finalize_no_show_detection")

    ActiveRecord::Migration.suppress_messages { migration.down }
    Booking.reset_column_information

    expect(booking.reload.status).to eq("review_no_show")
    expect(booking_log.reload.new_value).to eq("status" => "review_no_show")
    expect(booking_log.metadata["correction_reason"]).to eq("finalize_no_show_review")
    expect(room_log.reload.attributes).to include(
      "old_status" => "review_due_out",
      "new_status" => "review_no_show",
      "event_type" => "review_no_show_cancelled"
    )
    expect(night_audit.reload.summary).to include(
      "review_no_show_count" => 2,
      "note" => "review_no_show"
    )
    expect(night_audit.exceptions.keys).to contain_exactly("review_no_show", "review_due_out")
    expect(night_log.reload.metadata).to include(
      "reviewed_no_show_count" => 2,
      "reviewed_due_out_count" => 1,
      "type" => "review_due_out"
    )
    expect(folio_transaction.reload).to have_attributes(correction_reason: "finalize_no_show_review")
    expect(folio_transaction.metadata["override_reason"]).to eq("finalize_no_show_review")
    expect(financial_event.reload).to have_attributes(reason: "finalize_no_show_review")
    expect(financial_event.metadata["correction_reason"]).to eq("finalize_no_show_review")
  end
end
