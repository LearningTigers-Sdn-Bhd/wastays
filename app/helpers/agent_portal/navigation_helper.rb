# frozen_string_literal: true

module AgentPortal
  module NavigationHelper
    def agent_sidebar_sections
      @_agent_sidebar_sections ||= [
        PanelsUI::Navigation::Section.new(
          label: "Home",
          items: [
            PanelsUI::Navigation::Item.new(
              label: "Hotels",
              path: agent_hotels_path,
              search_text: "Hotels Create Hotel Owner Sign-in",
              active: controller_name == "hotels",
              icon: "building-2"
            )
          ]
        ),
        PanelsUI::Navigation::Section.new(
          label: "Account",
          items: [
            PanelsUI::Navigation::Item.new(
              label: "My account",
              path: edit_agent_profile_path,
              search_text: "My Account Profile Password",
              active: controller_name == "profiles",
              icon: "user"
            )
          ]
        )
      ]
    end
  end
end
