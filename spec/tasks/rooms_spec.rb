# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "rooms:audit_legacy_directory" do
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("rooms:audit_legacy_directory")
    Rake::Task["rooms:audit_legacy_directory"].reenable
  end

  it "reports a clean directory" do
    result = Rooms::AuditLegacyDirectory::Result.new(blocking_issues: [])
    allow(Rooms::AuditLegacyDirectory).to receive(:new).and_return(double(call: result))

    expect { Rake::Task["rooms:audit_legacy_directory"].invoke }
      .to output("Legacy room directory audit passed.\n").to_stdout
  end

  it "exits with a failure status when blocking issues exist" do
    issue = Rooms::AuditLegacyDirectory::Finding.new(
      code: :quantity_mismatch,
      hotel_id: 1,
      hotel_name: "Harbour Hotel",
      room_type_id: 2,
      room_type_name: "Deluxe",
      room_number: nil,
      message: "The quantity is 2, but the room-number list contains 1 value."
    )
    result = Rooms::AuditLegacyDirectory::Result.new(blocking_issues: [ issue ])
    allow(Rooms::AuditLegacyDirectory).to receive(:new).and_return(double(call: result))

    expect { Rake::Task["rooms:audit_legacy_directory"].invoke }
      .to output(/found 1 blocking issue.*quantity_mismatch/m).to_stdout
      .and raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
  end
end
