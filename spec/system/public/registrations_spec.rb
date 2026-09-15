require 'rails_helper'

RSpec.describe 'Hotel Registration', type: :system do
  before do
    driven_by(:rack_test)

    # Ensure some permissions exist for seeding
    Permission.find_or_create_by!(slug: 'manage_account') { |p| p.name = 'Manage Account' }
  end

  it 'describes registration without pricing claims' do
    visit register_path

    rendered_text = page.text(:all)
    expect(rendered_text).to include(
      'Create Your Property Account',
      'Guided Onboarding',
      'Complete your property details step by step.',
      'Guest Messaging',
      'Connect with guests through WhatsApp.',
      'One Property Workspace',
      'Manage rooms, rates, and bookings in one place.',
      'Your First Property',
      'Property Name',
      'Step-by-step guidance',
      'Save and continue later',
      'Review before going live'
    )

    removed_claims = [
      'Free to Join',
      'No setup fees',
      'No subscriptions',
      'Start Your Free Account',
      'No subscription fees',
      'Set up in minutes',
      'Pay only when you earn',
      'WhatsApp-Driven',
      'Revenue Growth',
      'Create Your Hotel Account',
      'Complete your hotel details step by step.',
      'One Hotel Workspace',
      'Your First Hotel',
      'Hotel Name'
    ]
    removed_claims.each { |claim| expect(rendered_text).not_to include(claim) }
    expect(page).to have_button('Register Your Property', visible: :all)
    expect(page).to have_no_button('Register Your Hotel', visible: :all)
  end

  it 'allows a new hotel to register' do
    visit register_path

    fill_in 'Company / Group Name', with: 'Green Hotel Group'
    fill_in 'Property Name', with: 'Green Hotel KL'
    fill_in 'City', with: 'Kuala Lumpur'
    choose 'Per guest'
    fill_in 'Full Name', with: 'Sarah Lim'
    fill_in 'Work Email', with: 'sarah@example.com'
    fill_in 'Password', with: 'password123'

    click_button 'Register Your Property'

    expect(page).to have_content('Welcome! Your hotel account has been created.')
    expect(page).to have_content('Welcome to WAStays!')

    user = User.find_by(email: 'sarah@example.com')
     expect(page).to have_current_path(hotel_dashboard_path(user.hotels.first))
    expect(user).to be_present
    expect(user.account.name).to eq('Green Hotel Group')
    expect(user.hotels.first.name).to eq('Green Hotel KL')
    expect(user.hotels.first.sell_mode).to eq('per_person')
    expect(user.roles.pluck(:slug)).to include('hotel_owner')
  end

  it 'shows errors for invalid input' do
    visit register_path

    fill_in 'Full Name', with: '' # Invalid
    click_button 'Register Your Property'

    expect(page).to have_content("Name can't be blank")
  end

  it 'requires a permanent charging model' do
    visit register_path

    fill_in 'Company / Group Name', with: 'Green Hotel Group'
    fill_in 'Property Name', with: 'Green Hotel KL'
    fill_in 'City', with: 'Kuala Lumpur'
    fill_in 'Full Name', with: 'Sarah Lim'
    fill_in 'Work Email', with: 'sarah@example.com'
    fill_in 'Password', with: 'password123'
    click_button 'Register Your Property'

    expect(page).to have_content("Sell mode can't be blank")
    expect(Hotel).not_to exist
  end
end
