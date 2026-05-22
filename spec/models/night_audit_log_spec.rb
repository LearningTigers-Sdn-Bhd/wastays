# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAuditLog, type: :model do
  describe "associations" do
    it { should belong_to(:night_audit) }
    it { should belong_to(:hotel) }
    it { should belong_to(:user).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:action_type) }
    it { should validate_inclusion_of(:action_type).in_array(NightAuditLog::ACTION_TYPES) }
  end
end
