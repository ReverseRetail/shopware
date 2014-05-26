require 'pp'

require 'shopware/cli/subcommands/mannol/import/models/product'
require 'shopware/cli/subcommands/mannol/import/models/variant'
require 'shopware/cli/subcommands/mannol/import/reader'
require 'shopware/cli/subcommands/mannol/import/validators/product'

module Shopware
  module CLI
    module Subcommands
      module Mannol
        module Import
          def self.included(thor)
            thor.class_eval do
              desc 'import [FILE]', 'Import products as a CSV file'
              option :root_category_id, type: :string, required: true
              option :car_manufacturer_category_id, type: :string, required: true
              option :defaults, type: :hash, default: {
                'price'                         => 999,
                'in_stock'                      => 15,
                'stockmin'                      => 1,
                'content_configurator_set_name' => 'Inhalt',
                'category_template'             => 'article_listing_1col.tpl'
              }
              def import(file)
                defaults = options.defaults

                if File.exist? file
                  info "Processing `#{File.basename file}`..." if options.verbose?

                  reader = Reader.new file, options.import['column_separator'], options.import['quote_character']

                  products = reader.products
                  quantity = products.length

                  info "Found #{quantity} product(s)." if options.verbose?

                  products = reader.products
                  quantity = products.length

                  products.each_with_index do |product, i|
                    index = i + 1

                    info "Processing #{index}. product “#{product.name}” of #{quantity}..." if options.verbose?

                    validator = Validators::Product.new product

                    if validator.valid?
                      article = @client.find_article_by_name product.name

                      if not article
                        categories = categories(product: product, options: options, defaults: defaults)

                        data = get_article_data(product: product, categories: categories, options: options, defaults: defaults)

                        article = @client.create_article data

                        if article
                          variants = product.variants

                          variants.sort! { |x, y| x.purchase_unit <=> y.purchase_unit }

                          variants.each do |variant|
                            data = get_variant_data(article: article, variant: variant, options: options, defaults: defaults)

                            variant = @client.create_variant data

                            if not variant
                              error 'Uuuuuppppss, something went wrong while creating variant.', indent: true if options.verbose?
                            end
                          end
                        else
                          error 'Uuuuuppppss, something went wrong while creating product.', indent: true if options.verbose?
                        end
                      else
                        warning 'Product already exists, skipping...', indent: true if options.verbose?
                      end
                    else
                      error 'Product is not valid, skipping...', indent: true if options.verbose?

                      validator.errors.each do |error|
                        property = error.first
                        label    = property.to_s.capitalize

                        error "#{label} not valid.", indent: true if options.verbose?
                      end
                    end
                  end

                  ok 'Import finished.'
                else
                  error "File: `#{file}` not found." if options.verbose?
                end
              end

              private

              def categories(product:, options:, defaults:)
                categories = []

                category = product.category

                if category
                  category = find_or_create_category(
                    name: category,
                    template: defaults['category_template'],
                    parent_id: options.root_category_id
                  )

                  if category
                    categories << category['id']

                    subcategory = product.subcategory

                    if subcategory
                      description = product.subcategory_description

                      subcategory = find_or_create_category(
                        name: subcategory,
                        text: description,
                        template: defaults['category_template'],
                        parent_id: category['id']
                      )

                      if subcategory
                        categories << subcategory['id']

                        subsubcategory = product.subsubcategory

                        if subsubcategory
                          subsubcategory = find_or_create_category(
                            name: subsubcategory,
                            template: defaults['category_template'],
                            parent_id: subcategory['id']
                          )

                          if subsubcategory
                            categories << subsubcategory['id']
                          else
                            error 'Uuuuuppppss, something went wrong while creating subsubcategory.', indent: true if options.verbose?
                          end
                        end
                      else
                        error 'Uuuuuppppss, something went wrong while creating subcategory.', indent: true if options.verbose?
                      end
                    end
                  else
                    error 'Uuuuuppppss, something went wrong while creating category.', indent: true if options.verbose?
                  end
                end

                car_manufacturer_categories = product.car_manufacturer_categories

                if not car_manufacturer_categories.empty?
                  car_manufacturer_categories.each do |car_manufacturer_category|
                    name = car_manufacturer_category[:name]

                    car_manufacturer_category = find_or_create_category(
                      name: name,
                      template: options.category_template,
                      parent_id: options.car_manufacturer_category_id
                    )

                    if car_manufacturer_category
                      categories << car_manufacturer_category['id']
                    else
                      error 'Uuuuuppppss, something went wrong while creating car manufacturer category.', indent: true if options.verbose?
                    end
                  end
                end

                car_categories = product.car_categories

                if not car_categories.empty?
                  car_categories.each do |car_category|
                    name             = car_category[:name]
                    car_manufacturer = car_category[:car_manufacturer]

                    car_manufacturer_category = find_or_create_category(
                      name: car_manufacturer,
                      template: options.category_template,
                      parent_id: options.car_manufacturer_category_id
                    )

                    if car_manufacturer_category
                      car_category = find_or_create_category(
                        name: name,
                        template: options.category_template,
                        parent_id: car_manufacturer_category['id']
                      )

                      if car_category
                        categories << car_category['id']
                      else
                        error 'Uuuuuppppss, something went wrong while creating car category.', indent: true if options.verbose?
                      end
                    else
                      error 'Uuuuuppppss, something went wrong while creating car manufacturer category for car category.', indent: true if options.verbose?
                    end
                  end
                end

                categories
              end

              def get_article_data(product:, categories:, options:, defaults:)
                data = {
                  name: product.name,
                  descriptionLong: product.description,
                  supplier: product.supplier,
                  tax: 19,
                  mainDetail: {
                    number: product.number,
                    prices: [
                      {
                        customerGroupKey: 'EK',
                        price: defaults['price']
                      }
                    ]
                  },
                  configuratorSet: {
                    groups: []
                  },
                  categories: [],
                  active: true
                }

                content_options = product.content_options

                if not content_options.empty?
                  content_configurator_set = {
                    name: defaults['content_configurator_set_name'],
                    options: []
                  }

                  content_options.each do |option|
                    content_configurator_set[:options] << { name: option } if option
                  end

                  data[:configuratorSet][:groups] << content_configurator_set if content_configurator_set
                end

                if not categories.empty?
                  categories.each do |category|
                    data[:categories] << { id: category }
                  end
                end

                data
              end

              def get_variant_data(article:, variant:, options:, defaults:)
                data = {
                  articleId: article['id'],
                  number: variant.number,
                  supplierNumber: variant.supplier_number,
                  additionaltext: variant.content,
                  purchaseUnit: variant.purchase_unit,
                  referenceUnit: variant.reference_unit,
                  unitId: variant.unit_id,
                  inStock: defaults['in_stock'],
                  stockmin: defaults['stockmin'],
                  prices: [
                    {
                      customerGroupKey: 'EK',
                      price: defaults['price']
                    }
                  ],
                  configuratorOptions: [],
                  active: true
                }

                content = variant.content

                if content
                  data[:configuratorOptions] << {
                    group: defaults['content_configurator_set_name'],
                    option: variant.content
                  }
                end

                data
              end

              def find_or_create_category(name:, template:, parent_id:, text: nil)
                transient = @client.find_category_by_name name

                if not transient
                  info "Category “#{name}” does not exists, creating new one...", indent: true if options.verbose?

                  properties = {
                    name: name,
                    cmsHeadline: name,
                    template: template,
                    parentId: parent_id
                  }

                  properties[:cmsText] = text if text and not text.empty?

                  category = @client.create_category properties

                  @client.get_category category['id']
                else
                  info "Category “#{name}” already exists.", indent: true if options.verbose?

                  transient
                end
              end

              def create_or_update_category(name:, template:, parent_id:, text: nil)
                transient = @client.find_category_by_name name

                properties = {
                  name: name,
                  cmsHeadline: name,
                  template: template,
                  parentId: parent_id
                }

                properties[:cmsText] = text if text and not text.empty?

                if not transient
                  info "Category “#{name}” does not exists, creating new one...", indent: true if options.verbose?

                  category = @client.create_category properties

                  @client.get_category category['id']
                else
                  info "Category “#{name}” already exists, updating category...", indent: true if options.verbose?

                  @client.update_category transient['id'], properties
                end
              end
            end
          end
        end
      end
    end
  end
end