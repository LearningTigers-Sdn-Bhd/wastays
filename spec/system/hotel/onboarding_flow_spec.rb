require 'rails_helper'

RSpec.describe 'Hotel Onboarding and Approval Flow', type: :system do
  before do
    driven_by(:rack_test)
    
    # Seed required data
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    CancellationPolicyTemplate.find_or_create_by!(name: 'Flexible', body: 'Full refund if cancelled 24h before.')
  end

  it 'completes the full onboarding and approval process' do
    # 1. Registration
    visit register_path
    fill_in 'Business / Company Name', with: 'Green Hotel Group'
    fill_in 'Hotel Name', with: 'Green Hotel KL'
    fill_in 'City', with: 'Kuala Lumpur'
    fill_in 'Full Name', with: 'Sarah Lim'
    fill_in 'Email Address', with: 'sarah@example.com'
    fill_in 'Password', with: 'password123'
    click_button 'Create Account'

    expect(page).to have_content('Welcome to WAStays!')
    hotel = Hotel.find_by(name: 'Green Hotel KL')

    # 2. Step 1: Profile
    within('#step-profile') { click_link 'Update' }
    fill_in 'Address', with: '123 Jalan Ampang'
    select '4 Star', from: 'Star Rating'
    click_button 'Save Profile'
    expect(page).to have_content('Hotel profile updated successfully.')

    # 3. Step 2: Policies
    within('#step-policies') { click_link 'Update' }
    fill_in 'Standard Check-in Time', with: '2:00 PM'
    fill_in 'Standard Check-out Time', with: '12:00 PM'
    click_button 'Use "Flexible" template'
    click_button 'Save Policies'
    expect(page).to have_content('Hotel policies updated successfully.')

    # 4. Step 3: Room Setup
    within('#step-rooms') { click_link 'Update' }
    click_link 'Add Room Type'
    fill_in 'Room Type Name', with: 'Deluxe Room'
    fill_in 'Max Adults', with: 2
    fill_in 'Max Children', with: 1
    fill_in 'Total Number of Rooms', with: 10
    fill_in 'Base Nightly Rate (MYR)', with: 180
    click_button 'Create Room Type'
    expect(page).to have_content('Room type created successfully.')

    # 5. Step 4: Submit for Review
    click_link 'Back to Dashboard'
    within('#step-review') { click_button 'Submit for Review' }
    expect(page).to have_content('Your hotel has been submitted for review.')
    expect(hotel.reload.status).to eq('pending_review')

    # 6. Superadmin Approval
    # Create superadmin
    superadmin = create(:user, :superadmin, email: 'admin@wastays.com')
    visit login_path
    fill_in 'Email', with: superadmin.email
    fill_in 'Password', with: 'password123'
    click_button 'Login'

    expect(page).to have_content('Welcome, Superadmin!')
    visit admin_hotels_path
    expect(page).to have_content('Green Hotel KL')
    expect(page).to have_content('Pending Review')
    
    click_link 'View'
    expect(page).to have_content('Deluxe Room')
    click_button 'Approve Hotel'

    expect(page).to have_content('Hotel has been approved.')
    expect(hotel.reload.status).to eq('approved')
  end
end
