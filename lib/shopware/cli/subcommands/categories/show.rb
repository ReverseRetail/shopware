require 'pp'
require 'terminal-table'

module Shopware
  module CLI
    module Subcommands
      module Categories
        module Show
          def self.included(thor)
            thor.class_eval do
              desc 'show ID', 'Show category with ID'
              class_option :dump, type: :boolean, default: false, aliases: '-d'
              def show(id)
                category = @client.get_category id

                if category
                  if options.dump
                    pp category
                  else
                    id             = category['id']
                    name           = category['name']
                    active         = category['active']
                    position       = category['position']
                    parent_id      = category['parentId']
                    children_count = category['childrenCount']
                    article_count  = category['articleCount']

                    table = Terminal::Table.new headings: ['Property', 'Value'] do |table|
                      table << ['ID', id]                         if id
                      table << ['Name', name]                     if name
                      table << ['Active', active]                 if active
                      table << ['Position', position]             if position
                      table << ['Parentable ID', parent_id]       if parent_id
                      table << ['Children count', children_count] if children_count
                      table << ['Article count', article_count]   if article_count
                    end

                    puts table
                  end
                else
                  info 'Category was not found.'
                end
              end
            end
          end
        end
      end
    end
  end
end