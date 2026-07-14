# frozen_string_literal: true

require "rails_helper"

RSpec.describe HousekeepingTasks::AssignStaff do
  let(:hotel) { create(:hotel) }
  let(:current_user) { create(:user) }

  describe "#call" do
    it "exists and can be instantiated" do
      service = described_class.new(
        hotel: hotel,
        request_id: 1,
        assigned_to_id: nil,
        current_user: current_user
      )
      expect(service).to respond_to(:call)
    end
  end
end
