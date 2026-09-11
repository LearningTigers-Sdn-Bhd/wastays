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

  it 'features and reorders the album without disturbing the open category form' do
    room_type = create(:room_type, hotel: hotel, name: 'Twin Room')
    %w[first.jpg second.jpg third.jpg].each do |filename|
      room_type.photos.attach(io: StringIO.new("room-#{filename}"), filename: filename, content_type: 'image/jpeg')
    end
    first_photo, second_photo, third_photo = room_type.photos.attachments.order(:id).to_a
    room_type.update!(featured_photo_attachment_id: first_photo.id)

    visit hotel_room_types_path(hotel)
    find("button[aria-label='Actions for Twin Room']").click
    click_link 'Edit details'

    expect(page).to have_css('dialog#edit-room-category-sheet[open]')
    # Scoped to the grid: the sheet footer carries its own Cancel for the
    # category form, and the album's Cancel only exists once a drag has
    # something to discard.
    within('#room-type-photos-manager') do
      expect(page).to have_button('Save Order', disabled: true)
      expect(page).to have_no_button('Cancel')
    end

    # Typed but unsaved. Featuring and reordering replace only the photo grid,
    # so this must still be here at the end.
    fill_in 'Room Category Name', with: 'Twin Room Deluxe'

    # Typing scrolled the sheet, and the driver reads the click coordinates
    # before the scroll settles — a press and a release on different pixels
    # never become a click. A real pointer does not move the page under itself.
    menu_trigger = find("button[aria-label='Actions for second.jpg']")
    page.scroll_to(menu_trigger)
    sleep 0.5
    menu_trigger.click

    click_button 'Set as featured'

    expect(page).to have_css('.toast', text: 'Featured photo updated successfully.')
    expect(room_type.reload.featured_photo_attachment_id).to eq(second_photo.id)
    expect(category_photo_ids).to eq([ second_photo.id, first_photo.id, third_photo.id ])

    drag_category_photo(third_photo.id, onto: first_photo.id, before: true)

    expect(category_photo_ids).to eq([ second_photo.id, third_photo.id, first_photo.id ])
    within('#room-type-photos-manager') do
      expect(page).to have_button('Save Order', disabled: false)
      expect(page).to have_button('Cancel')
    end

    click_button 'Save Order'

    expect(page).to have_css('.toast', text: 'Photo order saved successfully.')
    expect(room_type.reload.photo_order).to eq([ third_photo.id, first_photo.id ])
    expect(category_photo_ids).to eq([ second_photo.id, third_photo.id, first_photo.id ])
    expect(page).to have_button('Save Order', disabled: true)

    expect(page).to have_field('Room Category Name', with: 'Twin Room Deluxe')
    expect(page).to have_css('dialog#edit-room-category-sheet[open]')
  end

  # HTML5 drag events carry no coordinates a driver can synthesise, so the drag
  # is played out event by event. `before` picks the half of the target tile the
  # pointer lands on, which is what decides the insert side.
  def drag_category_photo(photo_id, onto:, before:)
    page.execute_script(<<~JS, photo_id.to_s, onto.to_s, before)
      const grid = document.querySelector("[data-photo-reorder-target='grid']")
      const dragged = grid.querySelector(`[data-photo-id="${arguments[0]}"]`)
      const target = grid.querySelector(`[data-photo-id="${arguments[1]}"]`)
      const rect = target.getBoundingClientRect()
      const clientX = arguments[2] ? rect.left + rect.width * 0.25 : rect.left + rect.width * 0.75

      const transfer = new DataTransfer()
      const fire = (name, element, extra = {}) => {
        const event = new Event(name, { bubbles: true, cancelable: true })
        Object.defineProperty(event, "dataTransfer", { value: transfer })
        Object.entries(extra).forEach(([key, value]) => Object.defineProperty(event, key, { value }))
        element.dispatchEvent(event)
      }

      fire("dragstart", dragged)
      fire("dragover", target, { clientX, clientY: rect.top + rect.height / 2 })
      fire("drop", target)
    JS
  end

  def category_photo_ids
    page.all("[data-photo-reorder-target='grid'] [data-photo-id]", visible: :all)
        .map { |tile| tile['data-photo-id'].to_i }
  end
end
