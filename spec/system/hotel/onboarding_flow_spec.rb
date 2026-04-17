require 'rails_helper'

RSpec.describe 'Hotel Onboarding and Approval Flow', type: :system do
  before do
    driven_by(:rack_test)

    # Seed required data
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    CancellationPolicyTemplate.find_or_create_by!(name: 'Flexible', body: 'Full refund if cancelled 24h before.')
  end

  it 'hides the full hotel navigation during onboarding and pending review' do
    hotel = create(:hotel, status: 'registered')
    user = create(:user, email: 'owner@example.com')
    role = create(:role, account: hotel.account, slug: 'hotel_owner', name: 'Hotel Owner')
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in 'Email Address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'

    expect(page).to have_content('Welcome to WAStays!')
    expect(page).to have_no_content('Rates & Inventory')
    expect(page).to have_no_content('Guests')
    expect(page).to have_no_content('Operation Logs')
    expect(page).to have_no_css("header[class*='lg:ps-64']")
    expect(page).to have_css('#step-profile .rounded-full', text: '1')
    expect(page).to have_no_content('<div class="flex-shrink-0 size-10 rounded-full')

    hotel.update!(status: 'pending_review')
    visit hotel_dashboard_path(hotel)

    expect(page).to have_no_content('Rates & Inventory')
    expect(page).to have_no_content('Guests')
    expect(page).to have_no_content('Operation Logs')
    expect(page).to have_no_css("header[class*='lg:ps-64']")
  end

  it 'completes the full onboarding and approval process' do
    # 1. Registration
    visit register_path
    fill_in 'Company / Group Name', with: 'Green Hotel Group'
    fill_in 'Hotel Name', with: 'Green Hotel KL'
    fill_in 'City', with: 'Kuala Lumpur'
    fill_in 'Full Name', with: 'Sarah Lim'
    fill_in 'Work Email', with: 'sarah@example.com'
    fill_in 'Password', with: 'password123'
    click_button 'Register Your Hotel'

    expect(page).to have_content('Welcome to WAStays!')
    hotel = Hotel.find_by(name: 'Green Hotel KL')

    # 2. Step 1: Profile
    within('#step-profile') { click_link 'Update' }
    fill_in 'Address', with: '123 Jalan Ampang'
    click_button 'Save Profile'
    expect(page).to have_content('Hotel profile updated successfully.')

    # 3. Step 2: Policies
    within('#step-policies') { click_link 'Update' }
    fill_in 'Standard Check-in Time', with: '14:00'
    fill_in 'Standard Check-out Time', with: '12:00'
    click_button 'Use "Flexible" template'
    click_button 'Save Policies'
    expect(page).to have_content('Hotel policies updated successfully.')

    # 4. Step 3: Room Setup
    within('#step-rooms') { click_link 'Update' }
    expect(page).to have_css("a.btn.btn-secondary", text: 'Back to Onboarding')
    expect(page).to have_xpath("//a[contains(@class,'btn') and contains(., 'Back to Onboarding')][following::nav[@aria-label='Breadcrumb']]")
    first(:link, 'Add Room Type').click
    expect(page).to have_css("a.btn.btn-secondary", text: 'Back to Onboarding')
    fill_in 'Room Type Name', with: 'Deluxe Room'
    fill_in 'Max Adults', with: 2
    fill_in 'Max Children', with: 1
    fill_in 'Total Number of Rooms', with: 10
    fill_in 'Base Nightly Rate (MYR)', with: 180
    click_button 'Create Room Type'
    expect(page).to have_content('Room type created successfully.')

    # 5. Step 4: Submit for Review
    click_link 'Back to Onboarding'
    within('#step-review') { click_button 'Submit for Review' }
    expect(page).to have_content('Your hotel has been submitted for review.')
    expect(page).to have_content('Pending Review')
    expect(page).to have_content('Our team is reviewing your hotel setup.')
    expect(page).to have_content('You will be able to access the full hotel system once your hotel is approved.')
    expect(page).to have_no_content('Arrival Board')
    expect(hotel.reload.status).to eq('pending_review')

    # 6. Superadmin Approval
    # Create superadmin
    Capybara.reset_sessions!
    superadmin = create(:user, :superadmin, email: 'admin@wastays.com')
    visit login_path
    fill_in 'Email Address', with: superadmin.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'

    expect(page).to have_content('Welcome, Superadmin!')
    visit admin_hotels_path
    expect(page).to have_content('Green Hotel KL')
    expect(page).to have_content('Pending Review')

    within('table') do
      expect(page).to have_link('Green Hotel KL', href: admin_hotel_path(hotel))
      click_link 'Green Hotel KL'
    end
    expect(page).to have_content('Deluxe Room')
    click_button 'Approve Hotel'

    expect(page).to have_content('Hotel has been approved.')
    expect(hotel.reload.status).to eq('approved')
  end
end
