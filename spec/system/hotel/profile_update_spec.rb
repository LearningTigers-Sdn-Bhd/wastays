require 'rails_helper'

RSpec.describe 'Hotel Profile Update', type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    driven_by(:cuprite)

    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Login
    sign_in_through_ui(user)
  end

  it 'allows the user to update the hotel profile' do
    visit edit_hotel_profile_path(hotel)

    expect(page).to have_css('h1', text: 'Property Details Settings')
    within('[data-testid="settings-tabs"]') do
      expect(page).to have_link('Hotel Details')
      expect(page).to have_link('Hotel Album', href: hotel_album_path(hotel))
    end

    within('#hotel-information') do
      expect(page).to have_link('See Hotel', href: hotel_path(hotel))

      fill_in 'Hotel Name', with: 'Updated Hotel Name'
      fill_in 'Description', with: 'A peaceful city retreat with locally inspired hospitality.'
      click_button 'Save'
    end

    expect(page).to have_css('.toast', text: 'Hotel profile updated successfully.')
    expect(hotel.reload.name).to eq('Updated Hotel Name')
    expect(hotel.description).to eq('A peaceful city retreat with locally inspired hospitality.')
    # The anchor drops the reader back at the section they saved rather than the
    # top of the page. Capybara strips fragments from current_path, so read the URL.
    expect(page.current_url).to end_with('#hotel-information')
    expect(page).not_to have_css('#hotel-faq-section')
  end

  it 'uploads, previews, and removes the hotel icon through the section form' do
    visit edit_hotel_profile_path(hotel)

    within('#hotel-information') do
      attach_file 'hotel_icon', Rails.root.join('public/icon.png'), make_visible: true
      expect(page).to have_css("img[alt='Preview of icon.png']")
      expect(page).to have_button('Save', disabled: false)
      click_button 'Save'
    end

    expect(page).to have_css('.toast', text: 'Hotel profile updated successfully.')
    expect(hotel.reload.icon).to be_attached

    within('#hotel-information') do
      find('.panel-dropzone__single-image').hover
      click_button 'Remove'
      expect(page).to have_text('Icon will be removed when you save.')
      expect(page).to have_button('Save', disabled: false)
      click_button 'Save'
    end

    expect(page).to have_css('.toast', text: 'Hotel profile updated successfully.')
    expect(hotel.reload.icon).not_to be_attached
  end

  it 'saves one section without touching the fields of another' do
    hotel.update!(contact_email: 'frontdesk@example.com')

    visit edit_hotel_profile_path(hotel)

    # Left pending in Hotel Information, and never submitted: the Hotel Location
    # Save below owns only its own fields.
    within('#hotel-information') { fill_in 'Hotel Name', with: 'Never Saved' }

    within('#hotel-location') do
      fill_in 'City', with: 'Kota Kinabalu'
      click_button 'Save'
    end

    expect(page).to have_css('.toast', text: 'Hotel profile updated successfully.')
    hotel.reload
    expect(hotel.city).to eq('Kota Kinabalu')
    expect(hotel.name).not_to eq('Never Saved')
    expect(hotel.contact_email).to eq('frontdesk@example.com')
  end

  it 'keeps each Save disabled and each Cancel hidden until its own section is edited' do
    visit edit_hotel_profile_path(hotel)

    within('#hotel-information') do
      expect(page).to have_button('Save', disabled: true)
      expect(page).to have_no_button('Cancel')
    end
    within('#hotel-location') { expect(page).to have_button('Save', disabled: true) }

    within('#hotel-information') do
      fill_in 'Hotel Name', with: 'Now Dirty'
      expect(page).to have_button('Save', disabled: false)
      expect(page).to have_button('Cancel')
    end

    # Editing one section does not arm the others.
    within('#hotel-location') do
      expect(page).to have_button('Save', disabled: true)
      expect(page).to have_no_button('Cancel')
    end
  end

  it 'discards the section back to its saved values when Cancel is clicked' do
    hotel.update!(name: 'Original Name', star_rating: 3)

    visit edit_hotel_profile_path(hotel)

    within('#hotel-information') do
      fill_in 'Hotel Name', with: 'Abandoned Edit'
      expect(page).to have_button('Cancel')

      click_button 'Cancel'

      expect(page).to have_field('Hotel Name', with: 'Original Name')
      # Back to clean: nothing left to save, nothing left to discard.
      expect(page).to have_button('Save', disabled: true)
      expect(page).to have_no_button('Cancel')
    end

    expect(hotel.reload.name).to eq('Original Name')
  end

  it 'queues and publishes a hotel album photo through the Panels UI dropzone' do
    visit hotel_album_path(hotel)

    arm_transition_wait("#hotel-photo-upload-sheet", property: "translate")
    click_button 'Upload Photos'
    expect(page).to have_css("dialog#hotel-photo-upload-sheet[open][data-panels-open]")
    wait_for_transition_end("#hotel-photo-upload-sheet")

    attach_file 'hotel_album_photos', Rails.root.join('spec/fixtures/files/sample_image.jpg'), make_visible: true

    expect(page).to have_css("[data-hotel-photo-queue-target='queueList'] [data-signed-id]", text: 'sample_image.jpg')
    expect(page).to have_css("[data-hotel-photo-queue-target='counterText']", text: '1 queued')

    within('dialog#hotel-photo-upload-sheet') do
      click_in_overlay find("button[aria-label='Close']")
    end
    expect(page).to have_no_css("dialog#hotel-photo-upload-sheet[open]")

    arm_transition_wait("#hotel-photo-upload-sheet", property: "translate")
    click_button 'Upload Photos'
    expect(page).to have_css("dialog#hotel-photo-upload-sheet[open][data-panels-open]")
    expect(page).to have_css("dialog#hotel-photo-upload-sheet[open] [data-signed-id]", text: 'sample_image.jpg')
    wait_for_transition_end("#hotel-photo-upload-sheet")

    click_in_overlay 'Confirm Upload'

    expect(page).to have_css("[aria-label='Published hotel photos'] .panel-attachment", text: 'sample_image.jpg')
    expect(hotel.reload.photos.count).to eq(1)
  end

  it 'uses a destructive alert dialog and removes a published photo live' do
    hotel.photos.attach(
      io: StringIO.new('published-photo'),
      filename: 'published.jpg',
      content_type: 'image/jpeg'
    )

    visit hotel_album_path(hotel)

    find("button[aria-label='Actions for published.jpg']").click
    click_button 'Remove photo'

    expect(page).to have_css("dialog#turbo-confirm-dialog[open][data-tone='destructive']")

    within('dialog#turbo-confirm-dialog') { click_in_overlay 'Cancel' }
    expect(hotel.reload.photos.count).to eq(1)

    find("button[aria-label='Actions for published.jpg']").click
    click_button 'Remove photo'
    within('dialog#turbo-confirm-dialog') { click_in_overlay 'Confirm' }

    expect(page).to have_no_css('#hotel-published-photos .panel-attachment', text: 'published.jpg')
    expect(page).to have_css('.toast', text: 'Hotel photo removed successfully.')
    expect(page).to have_current_path(hotel_album_path(hotel))
    expect(hotel.reload.photos.count).to eq(0)
  end

  it 'updates the featured photo live without leaving Hotel Album' do
    %w[first.jpg second.jpg].each do |filename|
      hotel.photos.attach(
        io: StringIO.new("published-photo-#{filename}"),
        filename: filename,
        content_type: 'image/jpeg'
      )
    end
    first_photo, second_photo = hotel.photos.attachments.order(:id).to_a
    hotel.update!(featured_photo_attachment_id: first_photo.id)

    visit hotel_album_path(hotel)

    find("button[aria-label='Actions for second.jpg']").click
    click_button 'Set as featured'

    second_card = find('#hotel-published-photos .panel-attachment', text: 'second.jpg')
    expect(second_card).to have_css('.panel-badge', text: 'Featured')
    expect(find('#hotel-published-photos .panel-attachment', text: 'first.jpg')).to have_no_css('.panel-badge', text: 'Featured')
    expect(page).to have_css('.toast', text: 'Featured photo updated successfully.')
    expect(page).to have_current_path(hotel_album_path(hotel))
    expect(hotel.reload.featured_photo_attachment_id).to eq(second_photo.id)
  end
end
