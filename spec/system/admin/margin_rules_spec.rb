require 'rails_helper'
require 'securerandom'

RSpec.describe 'Admin margin settings', type: :system do
  let(:token) { SecureRandom.hex(6) }
  let!(:account) { create(:account, name: "Margin Settings #{token}") }
  let!(:superadmin) { create(:user, :superadmin, account: account, email: "margin-admin-#{token}@example.com") }

  before do
    driven_by(:cuprite)

    sign_in_through_ui(superadmin)
    expect(page).to have_current_path(admin_dashboard_path, ignore_query: true)
  end

  it 'shows target id only for specific hotel or room type rules' do
    visit admin_margin_rules_path

    applies_to = find('select[name="margin_rule[settable_type]"]')

    expect(applies_to.value).to eq('')
    expect(page).to have_no_field('margin_rule_settable_id', visible: :visible)

    applies_to.find('option', text: 'Specific Hotel').select_option
    expect(page).to have_field('margin_rule_settable_id', visible: :visible)

    applies_to.find('option', text: 'Global Default').select_option
    expect(page).to have_no_field('margin_rule_settable_id', visible: :visible)

    applies_to.find('option', text: 'Specific Room Type').select_option
    expect(page).to have_field('margin_rule_settable_id', visible: :visible)
  end
end
