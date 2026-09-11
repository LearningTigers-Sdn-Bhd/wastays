require 'rails_helper'

RSpec.describe 'Room Setup', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Login
    sign_in_through_ui(user)
  end

  it 'allows the user to add a room category from Room Inventory' do
    visit hotel_room_types_path(hotel)

    expect(page).to have_content('No room categories found')
    first(:link, 'Create room category').click

    # Every section is on one scrollable sheet now — no tab to click through.
    fill_in 'Room Category Name', with: 'Deluxe Suite'
    fill_in 'Max Adults', with: 2
    fill_in 'Max Children', with: 1
    fill_in 'Total Number of Rooms', with: 5
    fill_in 'Standard Rate (MYR)', with: 250

    click_button 'Create Room Category'

    expect(page).to have_content('Room category created successfully.')
    expect(page).to have_content('Deluxe Suite')
    expect(page).to have_css(".panel-collapsible[data-state='closed']", text: 'Deluxe Suite')
    click_link 'Assign room rate'

    within '#assign-room-rate-sheet' do
      expect(page).to have_css('.panel-autocomplete', text: '')
      expect(page).to have_css('.panel-multi-select', text: 'Deluxe Suite')
      expect(page).to have_no_content('Guest pricing')
      click_button 'Cancel'
    end

    visit hotel_dashboard_path(hotel)
    expect(page).to have_current_path(hotel_dashboard_path(hotel))
    expect(page).to have_content('Rates & Inventory')
  end

  it 'attaches a room category photo from drag and drop, same as the Browse button' do
    room_type = create(:room_type, hotel: hotel, name: 'Twin Room')

    visit hotel_room_types_path(hotel)
    find("button[aria-label='Actions for Twin Room']").click
    click_link 'Edit details'

    expect(page).to have_css('dialog#edit-room-category-sheet[open]')
    expect(page).to have_css('#room-category-photos-heading')

    # Drag and drop assigns input.files directly, so this guards the staged file
    # against any change in how the dropzone announces a selection.
    encoded = Base64.strict_encode64(Rails.root.join('spec/fixtures/files/sample_image.jpg').binread)
    page.execute_script(<<~JS, encoded)
      const bytes = Uint8Array.from(atob(arguments[0]), (character) => character.charCodeAt(0))
      const transfer = new DataTransfer()
      transfer.items.add(new File([bytes], "dropped_room.jpg", { type: "image/jpeg" }))

      const event = new Event("drop", { bubbles: true, cancelable: true })
      Object.defineProperty(event, "dataTransfer", { value: transfer })
      document.querySelector("dialog#edit-room-category-sheet .panel-dropzone").dispatchEvent(event)
    JS

    expect(page).to have_css('.panel-attachment[data-file-key]', text: 'dropped_room.jpg', count: 1)

    # The Browse button adds to the same selection instead of replacing it.
    attach_file 'room_type_photos', Rails.root.join('public/icon.png'), make_visible: true
    expect(page).to have_css('.panel-attachment[data-file-key]', count: 2)

    click_button 'Save Changes'

    expect(page).to have_content('Room category updated successfully.')
    expect(room_type.reload.photos.map { |photo| photo.filename.to_s })
      .to match_array(%w[dropped_room.jpg icon.png])
  end
end
