# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::PreArrivalScheduler do
  include ActiveJob::TestHelper

  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, check_in: Date.current + 5.days, check_out: Date.current + 6.days) }

  before do
    ActiveJob::Base.queue_adapter = :test
    NotificationConfig.create!(
      hotel: hotel,
      notification_type: "pre_arrival_notification",
      enabled: true,
      channels: %w[whatsapp email],
      settings: { "stages" => %w[d2 d1] }
    )
  end

  it "creates one pending delivery per stage and channel" do
    deliveries = nil

    expect {
      deliveries = described_class.new(booking: booking).schedule!(trigger_event: "booking_confirmed")
    }.to change(NotificationDelivery, :count).by(4)

    deliver_jobs = enqueued_jobs.select { |job| job[:job] == Notifications::DeliverJob }
    expect(deliver_jobs.count).to eq(4)

    expect(deliveries.map { |d| d.payload["stage"] || d.payload[:stage] }).to match_array(%w[d2 d1 d2 d1])
  end

  it "dedupes by booking+stage+channel on repeated schedule calls" do
    scheduler = described_class.new(booking: booking)

    scheduler.schedule!(trigger_event: "booking_confirmed")
    expect {
      scheduler.schedule!(trigger_event: "booking_confirmed")
    }.not_to change(NotificationDelivery, :count)
  end

  it "marks past schedules as failed and does not enqueue" do
    near_booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day)

    expect {
      described_class.new(booking: near_booking).schedule!(trigger_event: "booking_confirmed")
    }.to change(NotificationDelivery, :count).by(4)

    expect(NotificationDelivery.where(booking: near_booking).pluck(:status).uniq).to eq([ "failed" ])
    deliver_jobs = enqueued_jobs.select { |job| job[:job] == Notifications::DeliverJob }
    expect(deliver_jobs).to be_empty
    expect(NotificationDelivery.where(booking: near_booking).pluck(:error_message).all? { |msg| msg.include?("in the past") }).to be(true)
  end

  it "reschedules only pending deliveries and keeps sent immutable" do
    scheduler = described_class.new(booking: booking)
    scheduler.schedule!(trigger_event: "booking_confirmed")

    sent_delivery = NotificationDelivery.where(booking: booking).first
    sent_delivery.update!(status: "sent", sent_at: Time.current)

    pending_before = NotificationDelivery.where(booking: booking, status: "pending").index_by(&:id)

    booking.update!(check_in: booking.check_in + 2.days, check_out: booking.check_out + 2.days)

    scheduler.reschedule_pending!(trigger_event: "booking_updated")

    expect(sent_delivery.reload.trigger_event).to eq("booking_confirmed")

    NotificationDelivery.where(id: pending_before.keys).find_each do |delivery|
      expect(delivery.trigger_event).to eq("booking_updated")
      expect(delivery.payload["scheduled_for"] || delivery.payload[:scheduled_for]).not_to eq(
        pending_before[delivery.id].payload["scheduled_for"] || pending_before[delivery.id].payload[:scheduled_for]
      )
    end
  end
end
