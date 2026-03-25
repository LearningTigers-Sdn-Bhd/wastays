require 'rails_helper'

RSpec.describe 'Hotel Registration', type: :system do
  before do
    driven_by(:rack_test)
    
    # Ensure some permissions exist for seeding
    Permission.find_or_create_by!(slug: 'manage_account') { |p| p.name = 'Manage Account' }
  end

  it 'allows a new hotel to register' do
    visit register_path

    fill_in 'Business / Company Name', with: 'Green Hotel Group'
    fill_in 'Hotel Name', with: 'Green Hotel KL'
    fill_in 'City', with: 'Kuala Lumpur'
    fill_in 'Full Name', with: 'Sarah Lim'
    fill_in 'Email Address', with: 'sarah@example.com'
    fill_in 'Password', with: 'password123'

    click_button 'Create Account'

    expect(page).to have_content('Welcome! Your hotel account has been created.')
    expect(page).to have_current_path(hotel_dashboard_path)
    
    user = User.find_by(email: 'sarah@example.com')
    expect(user).to be_present
    expect(user.account.name).to eq('Green Hotel Group')
    expect(user.hotels.first.name).to eq('Green Hotel KL')
    expect(user.roles.pluck(:slug)).to include('hotel_owner')
  end

  it 'shows errors for invalid input' do
    visit register_path

    fill_in 'Full Name', with: '' # Invalid
    click_button 'Create Account'

    expect(page).to have_content("Name can't be blank")
  end
end
