# frozen_string_literal: true

module Admin
  class BookingSourcesController < Admin::BaseController
    before_action :set_booking_source, only: [ :edit, :update, :toggle ]
    before_action :set_icon_names, only: [ :new, :create, :edit, :update ]

    def index
      @booking_sources = BookingSource.includes(logo_attachment: :blob).ordered
    end

    def new
      @booking_source = BookingSource.new(kind: "ota", active: true)
    end

    def edit; end

    def create
      attrs = booking_source_params
      attrs.delete(:remove_logo)
      @booking_source = BookingSource.new(attrs)
      @booking_source.position = BookingSource.next_position_for(@booking_source.kind)

      if @booking_source.save
        redirect_to admin_booking_sources_path, notice: "Booking source created."
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      attrs = booking_source_params
      remove_logo = attrs.delete(:remove_logo).to_s == "1"

      if @booking_source.update(attrs)
        @booking_source.remove_logo! if remove_logo && attrs[:logo].blank?
        redirect_to admin_booking_sources_path, notice: "Booking source updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def toggle
      @booking_source.update(active: !@booking_source.active)
      status = @booking_source.active? ? "activated" : "deactivated"
      redirect_to admin_booking_sources_path, notice: "Booking source '#{@booking_source.label}' #{status}."
    end

    def icon_preview
      name = params[:name].to_s
      @icon_name = name if BookingSource.available_icon_names.include?(name)
      render partial: "admin/booking_sources/icon_preview", locals: { icon_name: @icon_name }, layout: false
    end

    def reorder
      kind = params[:kind].to_s
      ordered_ids = Array(params[:ordered_ids]).map(&:to_i)
      return head :bad_request if kind.blank? || ordered_ids.empty?

      BookingSource.where(id: ordered_ids, kind: kind).each do |source|
        source.update_column(:position, ordered_ids.index(source.id))
      end
      BookingSource.reset_registry_cache!

      head :no_content
    end

    private

    def set_booking_source
      @booking_source = BookingSource.find(params[:id])
    end

    def set_icon_names
      @icon_names = BookingSource.available_icon_names
    end

    def booking_source_params
      params.require(:booking_source).permit(
        :key, :label, :kind, :icon, :badge_color, :badge_text_color, :badge_initial, :active, :logo, :remove_logo
      )
    end
  end
end
