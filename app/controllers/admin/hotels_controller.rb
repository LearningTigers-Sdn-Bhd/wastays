class Admin::HotelsController < ApplicationController
  before_action :authenticate_superadmin!
  before_action :set_hotel, only: [:show, :approve, :suspend]

  def index
    @hotels = Hotel.all.order(created_at: :desc)
  end

  def show
  end

  def approve
    if @hotel.update(status: 'approved')
      redirect_to admin_hotel_path(@hotel), notice: "Hotel has been approved."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to approve hotel."
    end
  end

  def suspend
    if @hotel.update(status: 'suspended')
      redirect_to admin_hotel_path(@hotel), notice: "Hotel has been suspended."
    else
      redirect_to admin_hotel_path(@hotel), alert: "Failed to suspend hotel."
    end
  end

  private

  def set_hotel
    @hotel = Hotel.find(params[:id])
  end
end
