# frozen_string_literal: true

module PanelsUI
  class Card < PanelsUI::BaseComponent
    class Media < PanelsUI::BaseComponent
      attr_reader :position

      POSITIONS = %i[top leading background].freeze
      RATIOS = %i[video wide square portrait auto].freeze

      def initialize(position: :top, ratio: :video, overlay: :default, class: nil, **attributes)
        @position = POSITIONS.include?(position) ? position : :top
        @ratio = RATIOS.include?(ratio) ? ratio : :video
        @overlay = @position == :background ? (overlay.presence || :default) : nil
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        validate_image_alternatives!
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        attributes[:aria] = (attributes[:aria] || {}).merge(hidden: "true") if @position == :background

        tag.div(**attributes.merge(
          class: tw_merge("panel-card__media", @class),
          data: data.merge(position: @position, ratio: @ratio, overlay: @overlay).compact
        )) do
          safe_join([ content, (tag.span("", class: "panel-card__media-overlay", aria: { hidden: "true" }) if @position == :background) ].compact)
        end
      end

      private

      def validate_image_alternatives!
        return if @position == :background

        fragment = Nokogiri::HTML5.fragment(content.to_s)
        invalid = fragment.css("img").any? { |image| !image.key?("alt") || image["alt"].blank? }
        raise ArgumentError, "Card media images require meaningful alt text" if invalid
      end
    end

    class Header < PanelsUI::BaseComponent
      renders_one :badges
      renders_one :actions

      HEADING_TAGS = %i[h2 h3 h4 h5 h6 p].freeze

      def initialize(title: nil, description: nil, primary_href: nil, title_as: :h3, class: nil, **attributes)
        @title = title
        @description = description
        @primary_href = primary_href
        @title_as = HEADING_TAGS.include?(title_as) ? title_as : :h3
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def primary_link? = @primary_href.present?

      def call
        attributes = @attributes.merge(class: tw_merge("panel-card__header", @class))
        tag.header(**attributes) do
          safe_join([
            (tag.div(badges, class: "panel-card__badges") if badges?),
            header_row,
            (tag.div(content, class: "panel-card__header-content") if content.present?)
          ].compact)
        end
      end

      private

      def header_row
        return unless @title.present? || @description.present? || actions?

        tag.div(class: "panel-card__header-row") do
          safe_join([
            (tag.div(safe_join([
              title_element,
              (tag.p(@description, class: "panel-card__description") if @description.present?)
            ].compact), class: "panel-card__heading") if @title.present? || @description.present?),
            (tag.div(actions, class: "panel-card__actions") if actions?)
          ].compact)
        end
      end

      def title_element
        return unless @title.present?

        title_content = if primary_link?
          helpers.link_to(@title, @primary_href, class: "panel-card__primary-link")
        else
          @title
        end
        tag.public_send(@title_as, title_content, class: "panel-card__title")
      end
    end

    class Content < PanelsUI::BaseComponent
      def initialize(class: nil, **attributes)
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call = tag.div(content, **@attributes.merge(class: tw_merge("panel-card__content", @class)))
    end

    class Footer < PanelsUI::BaseComponent
      ALIGNS = %i[start center end between].freeze

      def initialize(align: :end, class: nil, **attributes)
        @align = ALIGNS.include?(align) ? align : :end
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        tag.footer(content, **attributes.merge(
          class: tw_merge("panel-card__footer", @class),
          data: data.merge(align: @align)
        ))
      end
    end

    renders_one :media, ->(**args) { Media.new(**args) }
    renders_one :header, ->(**args) { Header.new(**args) }
    renders_one :card_content, ->(**args) { Content.new(**args) }
    renders_one :footer, ->(**args) { Footer.new(**args) }

    WIDTHS = %i[narrow default expanded full].freeze
    ORIENTATIONS = %i[vertical horizontal].freeze
    DENSITIES = %i[compact default spacious].freeze
    VARIANTS = %i[default muted outlined elevated].freeze
    INTERACTIONS = [ false, :clickable ].freeze
    DIVIDERS = %i[automatic always none].freeze
    ROOT_TAGS = %i[div article section].freeze

    style base: "panel-card w-full max-w-2xl",
          variants: {
            width: {
              narrow: "max-w-md",
              default: "max-w-2xl",
              expanded: "max-w-5xl",
              full: "max-w-none"
            }
          },
          defaults: { width: :default }

    def initialize(width: :default, orientation: :vertical, density: :default,
                   variant: :default, interactive: false, dividers: :automatic,
                   as: :div, class: nil, **attributes)
      @width = WIDTHS.include?(width) ? width : :default
      @orientation = ORIENTATIONS.include?(orientation) ? orientation : :vertical
      @density = DENSITIES.include?(density) ? density : :default
      @variant = VARIANTS.include?(variant) ? variant : :default
      @interactive = INTERACTIONS.include?(interactive) ? interactive : false
      @dividers = DIVIDERS.include?(dividers) ? dividers : :automatic
      @as = ROOT_TAGS.include?(as) ? as : :div
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def before_render
      if @interactive == :clickable && (!header? || !header.primary_link?)
        raise ArgumentError, "Clickable cards require a header with primary_href"
      end
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      attributes.merge(
        class: class_for(width: @width, class_override: @class),
        data: data.merge(
          orientation: @orientation,
          density: @density,
          variant: @variant,
          interactive: (@interactive == :clickable ? "clickable" : "static"),
          dividers: @dividers,
          media_position: (media.position if media?)
        ).compact
      )
    end
  end
end
