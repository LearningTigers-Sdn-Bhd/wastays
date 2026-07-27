# frozen_string_literal: true

module PanelsUI
  class Navbar < PanelsUI::BaseComponent
    renders_one :brand
    renders_one :actions
    renders_one :profile

    def initialize(key:, navigation: true, sticky: true, class: nil, **attributes)
      @key = key.to_s
      @navigation = navigation
      @sticky = sticky
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    attr_reader :key

    def before_render
      raise ArgumentError, "Navbar key is required" if key.blank?
      raise ArgumentError, "Navbar brand slot is required" unless brand?
    end

    def navigation? = @navigation
    def mobile_sidebar_id = "#{key}-sidebar-mobile"

    def navbar_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("panel-navbar", @class),
        data: data.merge(sticky: @sticky.to_s)
      )
    end
  end
end
