# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "apexcharts", to: "https://ga.jspm.io/npm:apexcharts@4.3.0/dist/apexcharts.esm.js"
pin "signature_pad", to: "https://ga.jspm.io/npm:signature_pad@5.0.4/dist/signature_pad.umd.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@floating-ui/dom", to: "@floating-ui--dom.js" # @1.7.6
pin "focus-trap" # @8.2.2
pin "body-scroll-lock" # @4.0.0
pin "cally" # @0.8.0
pin "@floating-ui/core", to: "@floating-ui--core.js" # @1.7.5
pin "@floating-ui/utils", to: "@floating-ui--utils.js" # @0.2.11
pin "@floating-ui/utils/dom", to: "@floating-ui--utils--dom.js" # @0.2.11
pin "tabbable" # @6.5.0
pin "tom-select" # @2.6.2
pin "@orchidjs/sifter", to: "@orchidjs--sifter.js" # @1.1.0
pin "@orchidjs/unicode-variants", to: "@orchidjs--unicode-variants.js" # @1.1.2
