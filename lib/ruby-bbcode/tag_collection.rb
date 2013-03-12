module RubyBBCode
  class TagCollection
    def initialize(text, tags)
      @text = text
      @defined_tags = tags
      @tags_list = []
      @bbtree = {:nodes => []}
      @bbtree_depth = 0
      @bbtree_current_node = @bbtree
      
      @tag_info_collection = []
      @valid = true
      
      commence_scan
    end
    
    def commence_scan
      @text.scan(/((\[ (\/)? (\w+) ((=[^\[\]]+) | (\s\w+=\w+)* | ([^\]]*))? \]) | ([^\[]+))/ix) do |tag_info|
        require 'pry'
        
        
        ti = TagInfo.new(tag_info, @defined_tags)    # TODO:  ti should be a full fledged class, not just a hash... it should have methods like #handle_bracketed_item_as_text...
  
        ti.handle_unregistered_tags_as_text  # if the tag isn't in the @defined_tags list, then treat it as text
        
        # if it's text or if it's an opening tag...
        # originally:  !ti[:is_tag] or !ti[:closing_tag]
        if ti.element_is_text? or ti.element_is_opening_tag?
          
          left = !ti[:is_tag] and !ti.element_is_opening_tag?
          right = ti[:is_tag] and ti.element_is_opening_tag?
          # debugging
          if right
            #log("got here...")
            #log(ti[:closing_tag].inspect)
            #log(ti.tag_data.inspect)
          end
          
          # if it's an opening tag...
          # originally:  ti[:is_tag]
          if ti.element_is_opening_tag?
            tag = @defined_tags[ti[:tag].to_sym]
            
            unless ti.allowed_outside_parent_tags? or (@tags_list.length > 0 and tag[:only_in].include?(@tags_list.last.to_sym))
              #binding.pry
              # Tag does to be put in the last opened tag
              err = "[#{ti[:tag]}] can only be used in [#{tag[:only_in].to_sentence(RubyBBCode.to_sentence_bbcode_tags)}]"
              err += ", so using it in a [#{@tags_list.last}] tag is not allowed" if @tags_list.length > 0
              @valid = [err]  # TODO: Currently working on this...
              #return [err]
              return   # TODO:  refactor these returns so that they follow a case when style syntax...  I think this will break things
                       #  Like when you parse a huge string, and it contains 1 error at the top... it will stop scanning the file
                       #  when a return is struck because it's popping completely out of the class and won't have a chance to keep scanning
                       #  ... although wait a second... that's the current behavior isn't it??
            end
  
            if tag[:allow_tag_param] and ti[:params][:tag_param] != nil
              # Test if matches
              if ti[:params][:tag_param].match(tag[:tag_param]).nil?
                @valid = [tag[:tag_param_description].gsub('%param%', ti[:params][:tag_param])]
                return
              end
            end
          end
  
          if @tags_list.length > 0 and  @defined_tags[@tags_list.last.to_sym][:only_allow] != nil
            # Check if the found tag is allowed
            last_tag = @defined_tags[@tags_list.last.to_sym]
            allowed_tags = last_tag[:only_allow]
            if (!ti[:is_tag] and last_tag[:require_between] != true and ti[:text].lstrip != "") or (ti[:is_tag] and (allowed_tags.include?(ti[:tag].to_sym) == false))
              # Last opened tag does not allow tag
              err = "[#{@tags_list.last}] can only contain [#{allowed_tags.to_sentence(RubyBBCode.to_sentence_bbcode_tags)}] tags, so "
              err += "[#{ti[:tag]}]" if ti[:is_tag]
              err += "\"#{ti[:text]}\"" unless ti[:is_tag]
              err += ' is not allowed'
              @valid = [err]
              return
            end
          end
  
          # Validation of tag succeeded, add to @tags_list and/or bbtree
          if ti[:is_tag]
            tag = @defined_tags[ti[:tag].to_sym]
            @tags_list.push ti[:tag]
            element = {:is_tag => true, :tag => ti[:tag].to_sym, :nodes => [] }
            element[:params] = {:tag_param => ti[:params][:tag_param]} if tag[:allow_tag_param] and ti[:params][:tag_param] != nil
          else
            text = ti[:text]
            text.gsub!("\r\n", "\n")
            text.gsub!("\n", "<br />\n")
            element = {:is_tag => false, :text => text }
            if @bbtree_depth > 0
              tag = @defined_tags[@bbtree_current_node[:tag]]
              if tag[:require_between] == true
                @bbtree_current_node[:between] = ti[:text]
                if tag[:allow_tag_param] and tag[:allow_tag_param_between] and (@bbtree_current_node[:params] == nil or @bbtree_current_node[:params][:tag_param] == nil)
                  # Did not specify tag_param, so use between.
                  
                  # Check if valid
                  if ti[:text].match(tag[:tag_param]).nil?
                    @valid = [tag[:tag_param_description].gsub('%param%', ti[:text])]
                    return
                  end
                  
                  # Store as tag_param
                  @bbtree_current_node[:params] = {:tag_param => ti[:text]} 
                end
                element = nil
              end
            end
          end
          @bbtree_current_node[:nodes] << element unless element == nil
          if ti[:is_tag]
            # Advance to next level (the node we just added)
            @bbtree_current_node = element
            @bbtree_depth += 1
          end
        end
        
  
        if  ti[:is_tag] and ti[:closing_tag]
          if ti[:is_tag]
            tag = @defined_tags[ti[:tag].to_sym]
            
            if @tags_list.last != ti[:tag]
              @valid = ["Closing tag [/#{ti[:tag]}] does match [#{@tags_list.last}]"] 
              return
            end
            if tag[:require_between] == true and @bbtree_current_node[:between].blank?
              @valid = ["No text between [#{ti[:tag]}] and [/#{ti[:tag]}] tags."]
              return
            end
            @tags_list.pop
  
            # Find parent node (kinda hard since no link to parent node is available...)
            @bbtree_depth -= 1
            @bbtree_current_node = @bbtree
            @bbtree_depth.times { @bbtree_current_node = @bbtree_current_node[:nodes].last }
          end
        end
      end
    end
    
    def tags_list
      @tags_list
    end
    
    def bbtree
      @bbtree
    end
    
    def valid
      @valid
    end
    
  end
end