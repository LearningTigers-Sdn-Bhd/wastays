require "rails_helper"

RSpec.describe ErrorEvents::Record do
  def raised(message = "Boom", klass = StandardError)
    raise klass, message
  rescue klass => e
    e
  end

  def record(error, **options)
    described_class.call(error: error, handled: false, severity: :error, context: {}, source: "application.active_job", **options)
  end

  it "records an error with its class, message, source and trimmed backtrace" do
    event = record(raised("Boom"))

    expect(event).to have_attributes(error_class: "StandardError", message: "Boom", severity: "error", handled: false, source: "application.active_job")
    expect(event.backtrace).to be_present
  end

  it "filters secrets from the context" do
    event = record(raised, context: { password: "hunter2", booking_id: 7 })

    expect(event.context).to eq("password" => "[FILTERED]", "booking_id" => 7)
  end

  it "keeps plain values only, so an object in the context cannot cause a loop" do
    event = record(raised, context: { request: Object.new, nested: { ids: [ 1, 2 ] } })

    expect(event.context).to eq("request" => "Object", "nested" => { "ids" => [ 1, 2 ] })
  end

  it "drops a context that is too large" do
    event = record(raised, context: { blob: "x" * 20_000 })

    expect(event.context).to eq("truncated" => true)
  end

  it "ignores missing pages and bad requests" do
    expect { record(raised("No route", ActionController::RoutingError)) }.not_to change(ErrorEvent, :count)
    expect { record(raised("Gone", ActiveRecord::RecordNotFound)) }.not_to change(ErrorEvent, :count)
  end

  it "does not raise when the event cannot be saved" do
    allow(ErrorEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid)

    expect(record(raised)).to be_nil
  end

  it "records errors that Rails.error reports" do
    expect { Rails.error.report(raised("Reported #{SecureRandom.hex(3)}"), handled: true, severity: :warning) }
      .to change(ErrorEvent, :count).by(1)
    expect(ErrorEvent.order(:id).last).to have_attributes(handled: true, severity: "warning")
  end
end
