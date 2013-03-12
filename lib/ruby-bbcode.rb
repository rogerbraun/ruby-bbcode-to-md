require 'tags/tags'
require 'ruby-bbcode/debugging'
require 'ruby-bbcode/tag_info'

module RubyBBCode
  include BBCode::Tags

  @@to_sentence_bbcode_tags = {:words_connector => "], [", 
    :two_words_connector => "] and [", 
    :last_word_connector => "] and ["}

  def self.to_html(text, escape_html = true, additional_tags = {}, method = :disable, *tags)
    # We cannot convert to HTML if the BBCode is not valid!
    text = text.clone
    use_tags = @@tags.merge(additional_tags)

    if method == :disable then
      tags.each { |t| use_tags.delete(t) }
    else
      new_use_tags = {}
      tags.each { |t| new_use_tags[t] = use_tags[t] if use_tags.key?(t) }
      use_tags = new_use_tags
    end

    if escape_html
      text.gsub!('<', '&lt;')
      text.gsub!('>', '&gt;')
    end

    valid = parse(text, use_tags)
    raise valid.join(', ') if valid != true

    bbtree_to_html(@bbtree[:nodes], use_tags)
  end

  def self.is_valid?(text, additional_tags = {})
    parse(text, @@tags.merge(additional_tags));
  end

  def self.tag_list
    @@tags
  end

  protected
  def self.parse(text, tags = {})
    tags = @@tags if tags == {}
    tags_list = []
    @bbtree = {:nodes => []}
    bbtree_depth = 0
    bbtree_current_node = @bbtree
    text.scan(/((\[ (\/)? (\w+) ((=[^\[\]]+) | (\s\w+=\w+)* | ([^\]]*))? \]) | ([^\[]+))/ix) do |tag_info|
      require 'pry'
      #binding.pry
      
      ti = TagInfo.new(tag_info, tags)    # TODO:  ti should be a full fledged class, not just a hash... it should have methods like #handle_bracketed_item_as_text...

      ti.handle_unregistered_tags_as_text  # if the tag isn't in the tags list, then treat it as text
      
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
          tag = tags[ti[:tag].to_sym]
          
          unless ti.allowed_outside_parent_tags? or (tags_list.length > 0 and tag[:only_in].include?(tags_list.last.to_sym))
            # Tag does to be put in the last opened tag
            err = "[#{ti[:tag]}] can only be used in [#{tag[:only_in].to_sentence(@@to_sentence_bbcode_tags)}]"
            err += ", so using it in a [#{tags_list.last}] tag is not allowed" if tags_list.length > 0
            return [err]
          end

          if tag[:allow_tag_param] and ti[:params][:tag_param] != nil
            # Test if matches
            return [tag[:tag_param_description].gsub('%param%', ti[:params][:tag_param])] if ti[:params][:tag_param].match(tag[:tag_param]).nil?
          end
        end

        if tags_list.length > 0 and  tags[tags_list.last.to_sym][:only_allow] != nil
          # Check if the found tag is allowed
          last_tag = tags[tags_list.last.to_sym]
          allowed_tags = last_tag[:only_allow]
          if (!ti[:is_tag] and last_tag[:require_between] != true and ti[:text].lstrip != "") or (ti[:is_tag] and (allowed_tags.include?(ti[:tag].to_sym) == false))
            # Last opened tag does not allow tag
            err = "[#{tags_list.last}] can only contain [#{allowed_tags.to_sentence(@@to_sentence_bbcode_tags)}] tags, so "
            err += "[#{ti[:tag]}]" if ti[:is_tag]
            err += "\"#{ti[:text]}\"" unless ti[:is_tag]
            err += ' is not allowed'
            return [err]
          end
        end

        # Validation of tag succeeded, add to tags_list and/or bbtree
        if ti[:is_tag]
          tag = tags[ti[:tag].to_sym]
          tags_list.push ti[:tag]
          element = {:is_tag => true, :tag => ti[:tag].to_sym, :nodes => [] }
          element[:params] = {:tag_param => ti[:params][:tag_param]} if tag[:allow_tag_param] and ti[:params][:tag_param] != nil
        else
          text = ti[:text]
          text.gsub!("\r\n", "\n")
          text.gsub!("\n", "<br />\n")
          element = {:is_tag => false, :text => text }
          if bbtree_depth > 0
            tag = tags[bbtree_current_node[:tag]]
            if tag[:require_between] == true
              bbtree_current_node[:between] = ti[:text]
              if tag[:allow_tag_param] and tag[:allow_tag_param_between] and (bbtree_current_node[:params] == nil or bbtree_current_node[:params][:tag_param] == nil)
                # Did not specify tag_param, so use between.
                # Check if valid
                return [tag[:tag_param_description].gsub('%param%', ti[:text])] if ti[:text].match(tag[:tag_param]).nil?
                # Store as tag_param
                bbtree_current_node[:params] = {:tag_param => ti[:text]} 
              end
              element = nil
            end
          end
        end
        bbtree_current_node[:nodes] << element unless element == nil
        if ti[:is_tag]
          # Advance to next level (the node we just added)
          bbtree_current_node = element
          bbtree_depth += 1
        end
      end
      

      if  ti[:is_tag] and ti[:closing_tag]
        if ti[:is_tag]
          tag = tags[ti[:tag].to_sym]
          return ["Closing tag [/#{ti[:tag]}] does match [#{tags_list.last}]"] if tags_list.last != ti[:tag]
          return ["No text between [#{ti[:tag]}] and [/#{ti[:tag]}] tags."] if tag[:require_between] == true and bbtree_current_node[:between].blank?
          tags_list.pop

          # Find parent node (kinda hard since no link to parent node is available...)
          bbtree_depth -= 1
          bbtree_current_node = @bbtree
          bbtree_depth.times { bbtree_current_node = bbtree_current_node[:nodes].last }
        end
      end
    end
    return ["[#{tags_list.to_sentence((@@to_sentence_bbcode_tags))}] not closed"] if tags_list.length > 0

    true
  end


  def self.bbtree_to_html(node_list, tags = {})
    tags = @@tags if tags == {}
    text = ""
    node_list.each do |node|
      if node[:is_tag]
        tag = tags[node[:tag]]
        t = tag[:html_open].dup
        t.gsub!('%between%', node[:between]) if tag[:require_between]
        if tag[:allow_tag_param]
          if node[:params] and !node[:params][:tag_param].blank?
            match_array = node[:params][:tag_param].scan(tag[:tag_param])[0]
            index = 0
            match_array.each do |match|
              if index < tag[:tag_param_tokens].length
                t.gsub!("%#{tag[:tag_param_tokens][index][:token].to_s}%", tag[:tag_param_tokens][index][:prefix].to_s+match+tag[:tag_param_tokens][index][:postfix].to_s)
                index += 1
              end
            end
          else
            # Remove unused tokens
            tag[:tag_param_tokens].each do |token|
              t.gsub!("%#{token[:token]}%", '')
            end
          end
        end

        text += t
        text += bbtree_to_html(node[:nodes], tags) if node[:nodes].length > 0
        t = tag[:html_close]
        t.gsub!('%between%', node[:between]) if tag[:require_between]
        text += t
      else
        text += node[:text] unless node[:text].nil?
      end
    end
    text
  end
  
  def self.parse_youtube_id(url)
    #url = "http://www.youtube.com/watch?v=E4Fbk52Mk1w"
    url =~ /[vV]=([^&]*)/
    
    id = $1
    
    
    if id.nil?
      # when there is no match for v=blah, then maybe they just 
      # provided us with the ID the way the system used to work... 
      # just "E4Fbk52Mk1w"
      return url  
    else
      # else we got a match for an id and we can return that ID...
      return id
    end
  end
  
end

String.class_eval do
  # Convert a string with BBCode markup into its corresponding HTML markup
  def bbcode_to_html(escape_html = true, additional_tags = {}, method = :disable, *tags)
    RubyBBCode.to_html(self, escape_html, additional_tags, method, *tags)
  end
  
  # Replace the BBCode content of a string with its corresponding HTML markup
  def bbcode_to_html!(escape_html = true, additional_tags = {}, method = :disable, *tags)
    self.replace(RubyBBCode.to_html(self, escape_html, additional_tags, method, *tags))
  end

  # Check if string contains valid BBCode. Returns true when valid, else returns array with error(s)
  def is_valid_bbcode?
    RubyBBCode.is_valid?(self)
  end
end
