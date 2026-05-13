# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomBlocks", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: ["101"]) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    permission = Permission.find_by(slug: "manage_room_status") || create(:permission, slug: "manage_room_status")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "POST /create" do
    context "with valid parameters" do
      let(:valid_params) do
        {
          room_block: {
            room_type_id: room_type.id,
            room_number: "101",
            start_date: Date.current,
            end_date: Date.current + 2.days,
            block_type: "maintenance",
            reason: "Leaky faucet"
          }
        }
      end

      it "creates a new RoomBlock" do
        expect {
          post hotel_room_blocks_path(hotel), params: valid_params
        }.to change(RoomBlock, :count).by(1)
      end

      it "redirects back to the room status board" do
        post hotel_room_blocks_path(hotel), params: valid_params
        expect(response).to redirect_to(hotel_room_status_board_path(hotel))
        expect(flash[:notice]).to eq("Room blocked for maintenance.")
      end

      it "updates the room status to out_of_service" do
        post hotel_room_blocks_path(hotel), params: valid_params
        status = RoomStatus.find_by(hotel: hotel, room_number: "101")
        expect(status.status).to eq("out_of_service")
      end
    end

    context "with future date" do
      let(:future_params) do
        {
          room_block: {
            room_type_id: room_type.id,
            room_number: "101",
            start_date: Date.current + 1.day,
            end_date: Date.current + 2.days,
            block_type: "maintenance",
            reason: "Leaky faucet"
          }
        }
      end

      it "does not update the room status immediately" do
        create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")
        post hotel_room_blocks_path(hotel), params: future_params
        status = RoomStatus.find_by(hotel: hotel, room_number: "101")
        expect(status.status).to eq("ready")
      end
    end

    context "with invalid parameters" do
      let(:invalid_params) do
        {
          room_block: {
            room_type_id: room_type.id,
            room_number: "101",
            start_date: Date.current,
            end_date: Date.current - 1.day, # Invalid end date
            block_type: "maintenance",
            reason: ""
          }
        }
      end

      it "does not create a new RoomBlock" do
        expect {
          post hotel_room_blocks_path(hotel), params: invalid_params
        }.not_to change(RoomBlock, :count)
      end

      it "redirects back with an alert" do
        post hotel_room_blocks_path(hotel), params: invalid_params
        expect(response).to redirect_to(hotel_room_status_board_path(hotel))
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "DELETE /destroy" do
    let!(:room_block) { create(:room_block, hotel: hotel, room_type: room_type, room_number: "101") }

    it "destroys the requested room_block" do
      expect {
        delete hotel_room_block_path(hotel, room_block)
      }.to change(RoomBlock, :count).by(-1)
    end

    it "redirects back to the room status board" do
      delete hotel_room_block_path(hotel, room_block)
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(flash[:notice]).to eq("Maintenance block removed.")
    end

    it "updates the room status to ready" do
      # Set initial status to out_of_service
      room_status = RoomStatus.find_or_create_by!(hotel: hotel, room_type: room_type, room_number: "101")
      room_status.update!(status: "out_of_service")
      
      delete hotel_room_block_path(hotel, room_block)
      
      expect(room_status.reload.status).to eq("ready")
    end
  end

  describe "POST /finish" do
    let!(:room_block) { create(:room_block, hotel: hotel, room_type: room_type, room_number: "101", start_date: Date.current, end_date: Date.current + 2.days) }

    it "does not destroy the room_block" do
      expect {
        post finish_hotel_room_block_path(hotel, room_block)
      }.not_to change(RoomBlock, :count)
    end

    it "does not change the end_date" do
      original_end_date = room_block.end_date
      post finish_hotel_room_block_path(hotel, room_block)
      expect(room_block.reload.end_date).to eq(original_end_date)
    end

    it "sets completed_at to present" do
      post finish_hotel_room_block_path(hotel, room_block)
      expect(room_block.reload.completed_at).to be_present
    end

    it "redirects back to the room status board" do
      post finish_hotel_room_block_path(hotel, room_block)
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(flash[:notice]).to eq("Maintenance block finished.")
    end

    it "updates the room status to pending_cleaning" do
      # Set initial status to out_of_service
      room_status = RoomStatus.find_or_create_by!(hotel: hotel, room_type: room_type, room_number: "101")
      room_status.update!(status: "out_of_service")
      
      post finish_hotel_room_block_path(hotel, room_block)
      
      expect(room_status.reload.status).to eq("pending_cleaning")
    end
  end
end
