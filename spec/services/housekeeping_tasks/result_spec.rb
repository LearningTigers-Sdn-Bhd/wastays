# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::Result do
  it "carries the task on success" do
    result = described_class.success(task: "T")

    expect(result).to be_success
    expect(result.task).to eq("T")
    expect(result.error).to be_nil
  end

  it "names what went wrong on failure, with no task to show" do
    result = described_class.failure("Enter what needs doing.")

    expect(result).not_to be_success
    expect(result.task).to be_nil
    expect(result.error).to eq("Enter what needs doing.")
  end

  it "refuses a reader it has no answer for, rather than replying nil" do
    expect { described_class.success(task: "T").public_send(:room) }.to raise_error(NoMethodError)
  end
end
