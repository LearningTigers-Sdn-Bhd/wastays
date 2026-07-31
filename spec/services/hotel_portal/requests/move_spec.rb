require 'rails_helper'

RSpec.describe HotelPortal::Requests::Move do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Sena") }

  def move(request, to:, kind: "housekeeping")
    described_class.new(hotel: hotel, kind: kind, request_id: request.id, to: to).call
  end

  describe 'putting a request away' do
    let(:request) do
      create(:housekeeping_request, booking: booking, status: 'completed',
             completed_at: Time.current, archived_at: nil)
    end

    it 'archives it and says where it came from' do
      result = move(request, to: :archived)

      expect(result).to be_ok
      expect(request.reload.archived_at).to be_present
      expect(result.from_column.key).to eq(:completed)
      expect(result.to_column.key).to eq(:archived)
    end
  end

  describe 'taking one back out' do
    let(:request) do
      create(:housekeeping_request, booking: booking, status: 'completed',
             completed_at: Time.current, archived_at: Time.current)
    end

    # An archived request given a status but never restored would sit in a lane
    # the board reads as active while still being archived, and show in neither.
    it 'restores it before giving it the lane\'s status' do
      result = move(request, to: :completed)

      expect(result).to be_ok
      expect(request.reload.archived_at).to be_nil
      expect(request.status).to eq('completed')
    end

    it 'can be sent straight back to the open lane' do
      result = move(request, to: :housekeeping)

      expect(result).to be_ok
      expect(request.reload.archived_at).to be_nil
      expect(request.status).to eq('pending')
    end
  end

  describe 'what a lane will not take' do
    let(:complaint) { create(:complaint_request, booking: booking, status: 'pending', archived_at: nil) }

    it 'refuses a complaint in the housekeeping lane' do
      result = described_class.new(hotel: hotel, kind: "complaint", request_id: complaint.id, to: :housekeeping).call

      expect(result).not_to be_ok
      expect(result.error).to include("cannot go there")
      expect(complaint.reload.status).to eq('pending')
    end

    it 'refuses housekeeping in the complaints lane' do
      housekeeping = create(:housekeeping_request, booking: booking, status: 'pending', archived_at: nil)

      result = move(housekeeping, to: :complaint)

      expect(result).not_to be_ok
      expect(result.error).to eq("A housekeeping request cannot go there.")
      expect(housekeeping.reload.status).to eq('pending')
    end

    # A checkout request is raised by a guest checking out, so there is nothing a
    # drop there could mean that would not be inventing a record.
    it 'refuses anything dropped in the checkout lane' do
      housekeeping = create(:housekeeping_request, booking: booking, status: 'pending', archived_at: nil)

      expect(move(housekeeping, to: :checkout)).not_to be_ok
    end

    it 'refuses a lane it does not have' do
      housekeeping = create(:housekeeping_request, booking: booking, status: 'pending', archived_at: nil)

      expect(move(housekeeping, to: :minibar)).not_to be_ok
    end

    it 'refuses a move that would not move anything' do
      housekeeping = create(:housekeeping_request, booking: booking, status: 'pending', archived_at: nil)

      expect(move(housekeeping, to: :housekeeping)).not_to be_ok
    end
  end

  # The whole point of one endpoint: the drag and the button write the same word.
  it 'finishes a complaint the way the complaint model spells it' do
    complaint = create(:complaint_request, booking: booking, status: 'pending', archived_at: nil)

    result = described_class.new(hotel: hotel, kind: "complaint", request_id: complaint.id, to: :completed).call

    expect(result).to be_ok
    expect(complaint.reload.status).to eq('resolved')
  end

  it 'completes housekeeping when it is dropped in recently completed' do
    housekeeping = create(:housekeeping_request, booking: booking, status: 'pending', archived_at: nil)

    result = move(housekeeping, to: :completed)

    expect(result).to be_ok
    expect(housekeeping.reload.status).to eq('completed')
    expect(housekeeping.completed_at).to be_present
  end

  it 'completes checkout when it is dropped in recently completed' do
    checkout = create(:check_out_request, booking: booking, status: 'pending')

    result = move(checkout, to: :completed, kind: "checkout")

    expect(result).to be_ok
    expect(checkout.reload.status).to eq('completed')
    expect(checkout.completed_at).to be_present
  end

  it 'refuses a request belonging to another hotel' do
    other = create(:housekeeping_request, booking: create(:booking), status: 'pending', archived_at: nil)

    expect { move(other, to: :completed) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
