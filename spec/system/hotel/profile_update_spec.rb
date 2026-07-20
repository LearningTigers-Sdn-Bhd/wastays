require 'rails_helper'

RSpec.describe 'Hotel Profile Update', type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
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
    end

    within('#hotel-profile-section') do
      expect(page).to have_link('See Hotel', href: hotel_path(hotel))

      fill_in 'Hotel Name', with: 'Updated Hotel Name'
      fill_in 'Description', with: 'A peaceful city retreat with locally inspired hospitality.'
      fill_in 'Address', with: '123 New Street'
      click_button 'Save Settings'
    end

    expect(page).to have_css('.toast', text: 'Hotel profile updated successfully.')
    expect(hotel.reload.name).to eq('Updated Hotel Name')
    expect(hotel.description).to eq('A peaceful city retreat with locally inspired hospitality.')
    expect(page).to have_current_path(edit_hotel_profile_path(hotel))
    expect(page).not_to have_css('#hotel-faq-section')
  end

  it 'queues and publishes a hotel album photo through the Panels UI dropzone' do
    visit edit_hotel_profile_path(hotel)

    click_button 'Upload Photos'
    expect(page).to have_css("dialog#hotel-photo-upload-sheet[open][data-panels-open]")
    sleep 0.5

    attach_file 'hotel_album_photos', Rails.root.join('spec/fixtures/files/sample_image.jpg'), make_visible: true

    expect(page).to have_css("[data-hotel-photo-queue-target='queueList'] [data-signed-id]", text: 'sample_image.jpg')
    expect(page).to have_css("[data-hotel-photo-queue-target='counterText']", text: '1 queued')

    within('dialog#hotel-photo-upload-sheet') do
      find("button[aria-label='Close']").click
    end
    expect(page).to have_no_css("dialog#hotel-photo-upload-sheet[open]")

    click_button 'Upload Photos'
    expect(page).to have_css("dialog#hotel-photo-upload-sheet[open][data-panels-open]")
    expect(page).to have_css("dialog#hotel-photo-upload-sheet[open] [data-signed-id]", text: 'sample_image.jpg')
    sleep 0.5

    click_button 'Confirm Upload'

    expect(page).to have_css("[aria-label='Published hotel photos'] .panel-attachment", text: 'sample_image.jpg')
    expect(hotel.reload.photos.count).to eq(1)
  end

  it 'uses a destructive alert dialog and removes a published photo live' do
    hotel.photos.attach(
      io: StringIO.new('published-photo'),
      filename: 'published.jpg',
      content_type: 'image/jpeg'
    )

    visit edit_hotel_profile_path(hotel)

    find("button[aria-label='Actions for published.jpg']").click
    click_button 'Remove photo'

    expect(page).to have_css("dialog#turbo-confirm-dialog[open][data-tone='destructive']")

    within('dialog#turbo-confirm-dialog') { click_button 'Cancel' }
    expect(hotel.reload.photos.count).to eq(1)

    find("button[aria-label='Actions for published.jpg']").click
    click_button 'Remove photo'
    within('dialog#turbo-confirm-dialog') { click_button 'Confirm' }

    expect(page).to have_no_css('#hotel-published-photos .panel-attachment', text: 'published.jpg')
    expect(page).to have_css('.toast', text: 'Hotel photo removed successfully.')
    expect(page).to have_current_path(edit_hotel_profile_path(hotel))
    expect(hotel.reload.photos.count).to eq(0)
  end

  it 'updates the featured photo live without leaving Hotel Details' do
    %w[first.jpg second.jpg].each do |filename|
      hotel.photos.attach(
        io: StringIO.new("published-photo-#{filename}"),
        filename: filename,
        content_type: 'image/jpeg'
      )
    end
    first_photo, second_photo = hotel.photos.attachments.order(:id).to_a
    hotel.update!(featured_photo_attachment_id: first_photo.id)

    visit edit_hotel_profile_path(hotel)

    find("button[aria-label='Actions for second.jpg']").click
    click_button 'Set as featured'

    second_card = find('#hotel-published-photos .panel-attachment', text: 'second.jpg')
    expect(second_card).to have_css('.panel-badge', text: 'Featured')
    expect(find('#hotel-published-photos .panel-attachment', text: 'first.jpg')).to have_no_css('.panel-badge', text: 'Featured')
    expect(page).to have_css('.toast', text: 'Featured photo updated successfully.')
    expect(page).to have_current_path(edit_hotel_profile_path(hotel))
    expect(hotel.reload.featured_photo_attachment_id).to eq(second_photo.id)
  end
end
