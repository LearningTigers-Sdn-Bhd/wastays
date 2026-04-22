require 'rails_helper'

RSpec.describe RolePermission, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:role) }
    it { is_expected.to belong_to(:permission) }
  end
end
