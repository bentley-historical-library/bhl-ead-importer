class BHLEADConverter < EADConverter

  def self.import_types(show_hidden = false)
    [
     {
       :name => "bhl_ead_xml",
       :description => "Import BHL EAD records from an XML file"
     }
    ]
  end


  def self.instance_for(type, input_file)
    if type == "bhl_ead_xml"
      self.new(input_file)
    else
      nil
    end
  end

  def self.profile
    "Convert EAD To ArchivesSpace JSONModel records"
  end

  def format_content(content)
    super.gsub(/[, ]+$/,"") # Remove trailing commas and spaces
  end

  def self.configure
    super

# BEGIN UNITID CUSTOMIZATIONS
# Let's take those brackets off of unitids and just add them in the exporter

    with 'unitid' do |node|
      ancestor(:note_multipart, :resource, :archival_object) do |obj|
        case obj.class.record_type
        when 'resource'
          # inner_xml.split(/[\/_\-\.\s]/).each_with_index do |id, i|
          #   set receiver, "id_#{i}".to_sym, id
          # end
          set obj, :id_0, inner_xml
        when 'archival_object'
          set obj, :component_id, inner_xml.gsub("[","").gsub("]","").strip
        end
      end
    end

# BEGIN TITLEPROPER AND AUTHOR CUSTOMIZATIONS

# The stock ArchivesSpace converter sets the author and titleproper elements each time it finds a titleproper or author elements
# This means that it first creates the elements using titlestmt/author and titlestmt/titleproper, and then overwrites the values when it reaches titlepage
# We want to use the titlepage statements. Changing this to be more explicit about using the statement that we want, and to remove some unwanted linebreaks.
    
# The EAD importer ignores titlepage; we need to unignore it
    with "titlepage" do
      @ignore = false
    end

    with 'titlepage/titleproper' do
      type = att('type')
      title_statement = inner_xml.gsub("<lb/>"," <lb/>")
      case type
      when 'filing'
        set :finding_aid_filing_title, title_statement.gsub("<lb/>","").gsub(/<date(.*?)<\/date>/,"").gsub(/\s+/," ").strip
      else
        set :finding_aid_title, title_statement.gsub("<lb/>","").gsub(/<date(.*?)<\/date>/,"").gsub(/\s+/," ").strip
      end
    end

    with 'titlepage/author' do
      author_statement = inner_xml.gsub("<lb/>"," <lb/>")
      set :finding_aid_author, author_statement.gsub("<lb/>","").gsub(/\s+/," ").strip
    end

# Skip the titleproper and author statements from titlestmt
    with 'titlestmt/titleproper' do
      next
    end

    with 'titlestmt/author' do
      next
    end

# Skip these to override the default ArchiveSpace functionality, which searches for a titleproper or an author anywhere
    with 'titleproper' do
      next
    end

    with 'author' do
      next
    end

# END TITLEPROPER CUSTOMIZATIONS

# BEGIN CLASSIFICATION CUSTOMIZATIONS

# In our EADs, the most consistent way that MHC and UARP finding aids are identified is via the titlepage/publisher
# In ArchivesSpace, we will be using Classifications to distinguish between the two
# This modification will link the resource being created to the appropriate Classification in ArchivesSpace

  with 'classification' do
    set :classifications, {'ref' => att('ref')}
  end

# END CLASSIFICATION CUSTOMIZATIONS
    
# BEGIN CHRONLIST CUSTOMIZATIONS

# For some reason the stock importer doesn't separate <chronlist>s out of notes like it does with <list>s
# Like, it includes the mixed content <chronlist> within the note text and also makes a chronological list, duplicating the content
# The addition of (split_tag = 'chronlist') to the insert_into_subnotes method call here fixes that
    with 'chronlist' do
      if  ancestor(:note_multipart)
        left_overs = insert_into_subnotes(split_tag = 'chronlist')
      else 
        left_overs = nil 
        make :note_multipart, {
          :type => node.name,
          :persistent_id => att('id'),
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
      end
      
      make :note_chronology do |note|
        set ancestor(:note_multipart), :subnotes, note
      end
      
      # and finally put the leftovers back in the list of subnotes...
      if ( !left_overs.nil? && left_overs["content"] && left_overs["content"].length > 0 ) 
        set ancestor(:note_multipart), :subnotes, left_overs 
      end 
    end

# END CHRONLIST CUSTOMIZATIONS

    
# BEGIN BIBLIOGRAPHY CUSTOMIZATIONS
    
# Our bibliographies are really more like general notes with paragraphs, lists, etc. We don't have any bibliographies
# that are simply a collection of <bibref>s, and all of the bibliographies that do have <bibref>s have them inserted into
# items in lists. This change will import bibliographies as a general note, which is really more appropriate given their content
    
    with 'bibliography' do |node|
      content = inner_xml.tap {|xml|
          xml.sub!(/<head>.*?<\/head>/m, '')
          # xml.sub!(/<list [^>]*>.*?<\/list>/m, '')
          # xml.sub!(/<chronlist [^>]*>.*<\/chronlist>/m, '')
        }

        make :note_multipart, {
          :type => 'odd',
          :persistent_id => att('id'),
          :subnotes => {
            'jsonmodel_type' => 'note_text',
            'content' => format_content( content )
          }
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
      end

    %w(bibliography index).each do |x|
      next if x == 'bibliography'
      with "index/head" do |node|
        set :label,  format_content( inner_xml )
      end

      with "index/p" do
        set :content, format_content( inner_xml )
      end
    end


    with 'bibliography/bibref' do
      next
    end
    
    with 'bibliography/p' do
        next
    end
    
    with 'bibliography/head' do
        next
    end

# END BIBLIOGRAPHY CUSTOMIZATIONS


# BEGIN BLOCKQUOTE P TAG FIX
# The ArchivesSpace EAD importer replaces all <p> tags with double line breaks
# This leads to too many line breaks surrounding closing block quote tags
# On export, this invalidates the EAD
# The following code is really hacky workaround to reinsert <p> tags within <blockquote>s
# Note: We only have blockquotes in bioghists and scopecontents, so call modified_format_content on just this block is sufficient
    
  # This function calls the regular format_content function, and then does a few other things, like preserving blockquote p tags and removing opening and closing parens from some notes, before returning the content
    def modified_format_content(content, note)
      content = format_content(content)
      # Remove parentheses from single-paragraph odds
      blocks = content.split("\n\n")
      if blocks.length == 1
        case note
        when 'odd','abstract','accessrestrict','daodesc'
          if content =~ /^\((.*?)\)$/
            content = $1
          elsif content =~ /^\[(.*?)\]$/
            content = $1
          end
        end
      end
      content.gsub(/<blockquote>\s*?/,"<blockquote><p>").gsub(/\s*?<\/blockquote>/,"</p></blockquote>")
    end

    %w(accessrestrict accessrestrict/legalstatus \
       accruals acqinfo altformavail appraisal arrangement \
       bioghist custodhist dimensions \
       fileplan odd otherfindaid originalsloc phystech \
       prefercite processinfo relatedmaterial scopecontent \
       separatedmaterial userestrict ).each do |note|
      with note do |node|
        content = inner_xml.tap {|xml|
          xml.sub!(/<head>.*?<\/head>/m, '')
          # xml.sub!(/<list [^>]*>.*?<\/list>/m, '')
          # xml.sub!(/<chronlist [^>]*>.*<\/chronlist>/m, '')
        }


        make :note_multipart, {
          :type => node.name,
          :persistent_id => att('id'),
          :publish => true,
          :subnotes => {
            'jsonmodel_type' => 'note_text',
            'content' => modified_format_content( content, note )
          }
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
      end
    end

# END BLOCKQUOTE P TAG FIX

# BEGIN CONDITIONAL SKIPS

# We have lists and indexes with all sorts of crazy things, like <container>, <physdesc>, <physloc>, etc. tags within <item>  or <ref> tags
# So, we need to tell the importer to skip those things only when they appear in places where they shouldn't, otherwise do
# it's normal thing
# REMINDER: If using the container management plugin, add the line 'next if context == :note_orderedlist' to "with 'container' do" in
# the converter_extra_container_values mixin

    %w(abstract langmaterial materialspec physloc).each do |note|
      next if note == "langmaterial"
      with note do |node|
        next if context == :note_orderedlist # skip these
        next if context == :items # these too
        content = inner_xml
        next if content =~ /\A<language langcode=\"[a-z]+\"\/>\Z/


        if content.match(/\A<language langcode=\"[a-z]+\"\s*>([^<]+)<\/language>\Z/)
          content = $1
        end

        make :note_singlepart, {
          :type => note,
          :persistent_id => att('id'),
          :publish => true,
          :content => modified_format_content( content.sub(/<head>.*?<\/head>/, ''), note )
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
      end
    end
    

    with 'list' do
      next if ancestor(:note_index)
      if  ancestor(:note_multipart)
        left_overs = insert_into_subnotes 
      else 
        left_overs = nil 
        make :note_multipart, {
          :type => 'odd',
          :persistent_id => att('id'),
          :publish => true,
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
      end
      
      
      # now let's make the subnote list 
      type = att('type')
      if type == 'deflist' || (type.nil? && inner_xml.match(/<deflist>/))
        make :note_definedlist do |note|
          set ancestor(:note_multipart), :subnotes, note
        end
      else
        make :note_orderedlist, {
          :enumeration => att('numeration')
        } do |note|
          set ancestor(:note_multipart), :subnotes, note
        end
      end
      
      
      # and finally put the leftovers back in the list of subnotes...
      if ( !left_overs.nil? && left_overs["content"] && left_overs["content"].length > 0 ) 
        set ancestor(:note_multipart), :subnotes, left_overs 
      end 
    
    end

    with 'list/head' do |node|
      ancestor(:note_definedlist, :note_orderedlist) do |obj|
        next if obj.title
        obj.title = format_content( inner_xml)
      end
    end
    
    with 'list/item' do
        # Okay this is another one of those hacky things that work
        # The problem: we have many items nested within items, like <list><item>First item <list><item>Subitem</item></list></item></list>
        # This would make one item like:
        #   First item <list><item>Subitem</item></list>
        # And another like:
        #   Subitem
        # ArchivesSpace lists are flat and do not allow for nesting lists within lists within items within lists within.. (you get the idea)...
        # Now, it would be nice to have a better way to tell the importer to only account for subitems one time, but there doesn't seem to be
        # With this modification we can change nested lists to <sublist> and nested items to <subitem> before migration
        # That way, the importer will ignore those sublists and subitems and sub out those tags for the correct tags
        set :items, inner_xml.gsub("<sublist","<list").gsub("<subitem","<item").gsub("</subitem>","</item>").gsub("</sublist>","</list>") if context == :note_orderedlist
    end

# END CONDITIONAL SKIPS

# BEGIN CONTAINER MODIFICATIONS
# Skip containers that appear in lists
# Don't downcase the instance_label
# Import att('type') as the container type for top containers, att('label') as the container type for subcontainers


# example of a 1:many tag:record relation (1+ <container> => 1 instance with 1 container)


    with 'container' do

        next if context == :note_orderedlist

        @containers ||= {}

        # we've found that the container has a parent att and the parent is in
        # our queue
        if att("parent") && @containers[att('parent')]
          cont = @containers[att('parent')]

        else
          # there is not a parent. if there is an id, let's check if there's an
          # instance before we proceed
          inst = context == :instance ? context_obj : context_obj.instances.last 
         
          # if there are no instances, we need to make a new one.
          # or, if there is an @id ( but no @parent) we can assume its a new
          # top level container that will be referenced later, so we need to
          # make a new instance
          if ( inst.nil? or  att('id')  )
            instance_label = att("label") ? att("label") : 'mixed_materials'

            if instance_label =~ /(.*)\s\[([0-9]+)\]$/
              instance_label = $1
              barcode = $2
            end

            make :instance, {
              :instance_type => instance_label
            } do |instance|
              set ancestor(:resource, :archival_object), :instances, instance
            end
            
            inst = context_obj
          end
        
          # now let's check out instance to see if there's a container...
          if inst.container.nil?
            make :container do |cont|
              set inst, :container, cont
            end
          end

          # and now finally we get the container. 
          cont =  inst.container || context_obj
          cont['barcode_1'] = barcode if barcode
          cont['container_profile_key'] = att("altrender")
        end

        # now we fill it in
        (1..3).to_a.each do |i|
          next unless cont["type_#{i}"].nil?
          if i == 1
            cont["type_#{i}"] = att('type')
          elsif i == 2 or i == 3
            cont["type_#{i}"] = att('label')
          end
          cont["indicator_#{i}"] = format_content( inner_xml )
          break
        end
        
        #store it here incase we find it has a parent
        @containers[att("id")] = cont if att("id")

    end
# END CONTAINER MODIFICATIONS

# BEGIN CUSTOM SUBJECT AND AGENT IMPORTS

# We'll be importing most of our subjects and agents separately and linking directly to the URI from our finding
# aids and accession records.
# This will check our subject, geogname, genreform, corpname, famname, and persname elements in our EADs for a ref attribute
# If a ref attribute is present, it will use that to link the agent to the resource.
# If there is no ref attribute, it will make a new agent as usual.
# We also have compound agents (agents with both a persname, corpname or famname and subdivided subject terms)
# In ArchivesSpace, this kind of agent can be represented in a resource by linking to the agent and adding terms/subdivisions
# within the resource. We will be accomplishing this by invalidating our EAD at some point (gasp!) to add <term> tags
# around the individual terms in a corpname, persname, or famname. This modification will also make sure that those terms
# get imported properly.

    {
      'function' => 'function',
      'genreform' => 'genre_form',
      'geogname' => 'geographic',
      'occupation' => 'occupation',
      'subject' => 'topical',
      'title' => 'uniform_title' # added title since we have some <title> tags in our controlaccesses
      }.each do |tag, type|
        with "controlaccess/#{tag}" do
          if att('ref')
            set ancestor(:resource, :archival_object), :subjects, {'ref' => att('ref')}
          else
            make :subject, {
                :terms => {'term' => inner_xml, 'term_type' => type, 'vocabulary' => '/vocabularies/1'},
                :vocabulary => '/vocabularies/1',
                :source => att('source') || 'ingest'
              } do |subject|
                set ancestor(:resource, :archival_object), :subjects, {'ref' => subject.uri}
                end
           end
        end
     end

    with 'origination/corpname' do
        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'creator'}
        else
            make_corp_template(:role => 'creator')
        end
    end

    with 'controlaccess/corpname' do
        corpname = Nokogiri::XML::DocumentFragment.parse(inner_xml)
        terms ||= []
        corpname.children.each do |child|
            if child.respond_to?(:name) && child.name == 'term'
                term = child.content.strip
                term_type = child['type']
                terms << {'term' => term, 'term_type' => term_type, 'vocabulary' => '/vocabularies/1'}
            end
        end
        
        relator = nil
        if att('encodinganalog') == '710'
            relator = 'ctb'
        end
        
        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'subject', 'terms' => terms, 'relator' => relator}
        else
            make_corp_template(:role => 'subject')
        end
    end

    with 'origination/famname' do
        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'creator'}
        else
            make_family_template(:role => 'creator')
        end
    end

    with 'controlaccess/famname' do
        famname = Nokogiri::XML::DocumentFragment.parse(inner_xml)
        terms ||= []
        famname.children.each do |child|
            if child.respond_to?(:name) && child.name == 'term'
                term = child.content.strip
                term_type = child['type']
                terms << {'term' => term, 'term_type' => term_type, 'vocabulary' => '/vocabularies/1'}
            end
        end
        
        relator = nil
        if att('encodinganalog') == '700'
            relator = 'ctb'
        end
        
        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'subject', 'terms' => terms, 'relator' => relator}
        else
            make_family_template(:role => 'subject')
        end
    end

    with 'origination/persname' do
        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'creator'}
        else
            make_person_template(:role => 'creator')
        end
    end

    with 'controlaccess/persname' do
        persname = Nokogiri::XML::DocumentFragment.parse(inner_xml)
        terms ||= []
        persname.children.each do |child|
            if child.respond_to?(:name) && child.name == 'term'
                term = child.content.strip
                term_type = child['type']
                terms << {'term' => term, 'term_type' => term_type, 'vocabulary' => '/vocabularies/1'}
            end
        end
        
        relator = nil
        if att('encodinganalog') == '700'
            relator = 'ctb'
        end
        
        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'subject', 'terms' => terms, 'relator' => relator}
        else
            make_person_template(:role => 'subject')
        end
    end

# END CUSTOM SUBJECT AND AGENT IMPORTS


# BEGIN PHYSDESC CUSTOMIZATIONS

# The stock EAD importer doesn't import <physfacet> and <dimensions> tags into extent objects; instead making them notes
# This is a corrected version

# first, some methods for generating note objects

def make_single_note(note_name, tag, tag_name="")
  content = tag.inner_text
  if !tag_name.empty?
    content = tag_name + ": " + content
  end
  make :note_singlepart, {
    :type => note_name,
    :persistent_id => att('id'),
    :publish => true,
    :content => format_content( content.sub(/<head>.?<\/head>/, '').strip)
  } do |note|
    set ancestor(:resource, :archival_object), :notes, note
  end
end

def make_nested_note(note_name, tag)
  content = tag.inner_text

  make :note_multipart, {
    :type => note_name,
    :persistent_id => att('id'),
    :publish => true,
    :subnotes => {
      'jsonmodel_type' => 'note_text',
      'content' => format_content( content )
    }
  } do |note|
    set ancestor(:resource, :archival_object), :notes, note
  end
end

with 'physdesc' do
  next if context == :note_orderedlist # skip these
  physdesc = Nokogiri::XML::DocumentFragment.parse(inner_xml)

  extent_number_and_type = nil

  dimensions = []
  physfacets = []
  container_summaries = []
  other_extent_data = []

  container_summary_texts = []
  dimensions_texts = []
  physfacet_texts = []

  # If there is already a portion specified, use it
  portion = att('altrender') || 'whole'

  physdesc.children.each do |child|
    # "extent" can have one of two kinds of semantic meanings: either a true extent with number and type,
    # or a container summary. Disambiguation is done through a regex.
    if child.name == 'extent'
      child_content = child.content.strip
      if extent_number_and_type.nil? && child_content =~ /^([0-9\.]+)+\s+(.*)$/
        extent_number_and_type = {:number => $1, :extent_type => $2}
      else
        container_summaries << child
        container_summary_texts << child.content.strip
      end

    elsif child.name == 'physfacet'
      physfacets << child
      physfacet_texts << child.content.strip

    elsif child.name == 'dimensions'
      dimensions << child
      dimensions_texts << child.content.strip

    elsif child.name != 'text'
      other_extent_data << child
    end
  end

  # only make an extent if we got a number and type, otherwise put all physdesc contents into a note
  if extent_number_and_type
    make :extent, {
      :number => $1,
      :extent_type => $2,
      :portion => portion,
      :container_summary => container_summary_texts.join('; '),
      :physical_details => physfacet_texts.join('; '),
      :dimensions => dimensions_texts.join('; ')
    } do |extent|
      set ancestor(:resource, :archival_object), :extents, extent
    end

  # there's no true extent; split up the rest into individual notes
  else
    container_summaries.each do |summary|
      make_single_note("physdesc", summary)
    end

    physfacets.each do |physfacet|
      make_single_note("physfacet", physfacet)
    end
    #
    dimensions.each do |dimension|
      make_nested_note("dimensions", dimension)
    end
  end

  other_extent_data.each do |unknown_tag|
    make_single_note("physdesc", unknown_tag, unknown_tag.name)
  end

end

# overwriting the default dimensions and physfacet functionality
with "dimensions" do
  next
end

with "physfacet" do
  next
end

# END PHYSDESC CUSTOMIZATIONS


# BEGIN LANGUAGE CUSTOMIZATIONS
# By default, ASpace just uses the last <language> tag it finds as the primary
# language of the material described. This results in incorrect finding-aid languages for many eads.

# for example, ead with the following <langmaterial> tag:

## <langmaterial>
##   The material is mostly in <language langcode="eng" encodinganalog="041">English</language>;
##   some correspondence is in <language langcode="arm" encodinganalog="041">Armenian;</language>;
##   select items are in <language langcode="ger" encodinganalog="041">German</language>.
## </langmaterial>

# will result in a primary material language of German.

# these changes fix that

with "langmaterial" do
  # first, assign the primary language to the ead
  langmaterial = Nokogiri::XML::DocumentFragment.parse(inner_xml)
  langmaterial.children.each do |child|
    if child.name == 'language'
      set ancestor(:resource, :archival_object), :language, child.attr("langcode")
      break
    end
  end

  # write full tag content to a note, subbing out the language tags
  content = inner_xml
  next if content =~ /\A<language langcode=\"[a-z]+\"\/>\Z/

  if content.match(/\A<language langcode=\"[a-z]+\"\s*>([^<]+)<\/language>\Z/)
    content = $1
  end

  make :note_singlepart, {
    :type => "langmaterial",
    :persistent_id => att('id'),
    :publish => true,
    :content => format_content( content.sub(/<head>.*?<\/head>/, '') )
  } do |note|
    set ancestor(:resource, :archival_object), :notes, note
  end
end

# overwrite the default langusage tag behavior
with "language" do
  next
end

# END LANGUAGE CUSTOMIZATIONS


# BEGIN INDEX CUSTOMIZATIONS

# The stock EAD converter creates separate index items for each indexentry,
# one for the value (persname, famname, etc) and one for the reference (ref),
# even when they are within the same indexentry and are related
# (i.e., the persname is a correspondent, the ref is a date or a location at which
# correspondence with that person can be found).
# The Bentley's <indexentry>s generally look something like:
# # <indexentry><persname>Some person</persname><ref>Some date or folder</ref></indexentry>
# # As the <persname> and the <ref> are associated with one another,
# we want to keep them together in the same index item in ArchiveSpace.

# This will treat each <indexentry> as one item,
# creating an index item with a 'value' from the <persname>, <famname>, etc.
# and a 'reference_text' from the <ref>.

with 'indexentry' do

  entry_type = ''
  entry_value = ''
  entry_reference = ''

  indexentry = Nokogiri::XML::DocumentFragment.parse(inner_xml)

  indexentry.children.each do |child|

    case child.name
      when 'name'
      entry_value << child.content
      entry_type << 'name'
      when 'persname'
      entry_value << child.content
      entry_type << 'person'
      when 'famname'
      entry_value << child.content
      entry_type << 'family'
      when 'corpname'
      entry_value << child.content
      entry_type << 'corporate_entity'
      when 'subject'
      entry_value << child.content
      entry_type << 'subject'
      when 'function'
      entry_value << child.content
      entry_type << 'function'
      when 'occupation'
      entry_value << child.content
      entry_type << 'occupation'
      when 'genreform'
      entry_value << child.content
      entry_type << 'genre_form'
      when 'title'
      entry_value << child.content
      entry_type << 'title'
      when 'geogname'
      entry_value << child.content
      entry_type << 'geographic_name'
    end

    if child.name == 'ref'
    entry_reference << child.content
    end

  end

  make :note_index_item, {
    :type => entry_type,
    :value => entry_value,
    :reference_text => entry_reference
    } do |item|
  set ancestor(:note_index), :items, item
  end
end

# Skip the stock importer actions to avoid confusion/duplication
{
      'name' => 'name',
      'persname' => 'person',
      'famname' => 'family',
      'corpname' => 'corporate_entity',
      'subject' => 'subject',
      'function' => 'function',
      'occupation' => 'occupation',
      'genreform' => 'genre_form',
      'title' => 'title',
      'geogname' => 'geographic_name'
    }.each do |k, v|
      with "indexentry/#{k}" do |node|
        next
      end
    end

    with 'indexentry/ref' do
       next
    end

# END INDEX CUSTOMIZATIONS

# BEGIN HEAD CUSTOMIZATIONS

# This issue is similar to the language issue -- if there is a note with multiple <head> elements (say, a bioghist with its own head and sublists with their own heads),
# the stock importer action is to set the note label to the very last <head> it finds. This modification will only set the label if it does not already exist, ensuring
# that it will only be set once.

    with 'head' do
      if context == :note_multipart
        ancestor(:note_multipart) do |note|
            next unless note["label"].nil?
        set :label, format_content( inner_xml )
        end
      elsif context == :note_chronology
        ancestor(:note_chronology) do |note|
            next unless note["title"].nil?
        set :title, format_content( inner_xml )
        end
      end
    end

# END HEAD CUSTOMIZATIONS

# BEGIN DAO TITLE CUSTOMIZATIONS

# The Bentley has many EADs with <dao> tags that lack title attributes.
# The stock ArchivesSpace EAD Converter uses each <dao>'s title attribute as
# the value for the imported digital object's title, which is a required property.
# As a result, all of our EADs with <dao> tags fail when trying to import into ArchivesSpace.
# This section of the BHL EAD Converter plugin modifies the stock ArchivesSpace EAD Converter
# by forming a string containing the digital object's parent archival object's title and date (if both exist),
# or just its title (if only the title exists), or just it's date (if only the date exists)
# and then using that string as the imported digital object's title.

with 'dao' do

  if att('ref') # A digital object has already been made
    make :instance, {
      :instance_type => 'digital_object',
      :digital_object => {'ref' => att('ref')}
       } do |instance|
    set ancestor(:resource, :archival_object), :instances, instance
    end
  else # Make a digital object
    make :instance, {
      :instance_type => 'digital_object'
      } do |instance|
    set ancestor(:resource, :archival_object), :instances, instance
    end
    # We'll use either the <dao> title attribute (if it exists) or our display_string (if the title attribute does not exist)
    # This forms a title string using the parent archival object's title, if it exists
    daotitle = nil
    ancestor(:archival_object ) do |ao|
      if ao.title && ao.title.length > 0
        daotitle = ao.title
      end
    end

    # This forms a date string using the parent archival object's date expression,
    # or its begin date - end date, or just it's begin date, if any exist
    # (Actually, we have expressions for all of our dates...let's just use those for the sake of simplicity)
    daodates = []
    ancestor(:archival_object) do |aod|
      if aod.dates && aod.dates.length > 0
        aod.dates.each do |dl|
          if dl['expression'].length > 0
            daodates << dl['expression']
          end
        end
      end
    end

    title = daotitle
    date_label = daodates.join(', ') if daodates.length > 0

    # This forms a display string using the parent archival object's title and date (if both exist),
    # or just its title or date (if only one exists)
    display_string = title || ''
    display_string += ', ' if title && date_label
    display_string += date_label if date_label

    make :digital_object, {
      :digital_object_id => SecureRandom.uuid,
      :title => att('title') || display_string,
      } do |obj|
        obj.file_versions <<  {
        :use_statement => att('role'),
        :file_uri => att('href'),
        :xlink_actuate_attribute => att('actuate'),
        :xlink_show_attribute => att('show')
        }
      set ancestor(:instance), :digital_object, obj
      end
    end
  end
end

    with 'daodesc' do

        ancestor(:digital_object) do |dobj|
          next if dobj.ref
        end
        
        make :note_digital_object, {
          :type => 'note',
          :persistent_id => att('id'),
          :content => modified_format_content(inner_xml.strip,'daodesc')
        } do |note|
          set ancestor(:digital_object), :notes, note
        end
    end

# END DAO TITLE CUSTOMIZATIONS


=begin
# Note: The following bits are here for historical reasons
# We have either decided against implementing the functionality OR the ArchivesSpace importer has changed, deprecating the following customizations
# START IGNORE
# Setting some of these to ignore because we have some physdesc, container, etc.
# Within list/items in our descgrps at the end of finding aids.
# Without setting these to ignore, ASpace both makes the list AND makes separate
# notes for physdesc, dimension, etc. and tries to make instances out of the
# containers, causing import errors.
# Note: if using this in conjunction with the Yale container management plugin,
# be sure to include the line 'next ignore if @ignore' within the with container do
# section of the ConverterExtraContainerValues module.
with 'archref/container' do
    @ignore = true
end
with 'archref/physdesc/dimensions' do
    @ignore = true
end
with 'archref/unittitle' do
    @ignore = true
end
with 'archref/unittitle/unitdate' do
    @ignore = true
end
with 'archref/note' do
    @ignore = true
end
with 'archref/note/p/unitdate' do
    @ignore = true
end
with 'archref/note/p/geogname' do
    @ignore = true
end
with 'unittitle' do |node|
    ancestor(:note_multipart, :resource, :archival_object) do |obj|
      unless obj.class.record_type == "note_multipart" or context == "note_orderedlist"
        title = Nokogiri::XML::DocumentFragment.parse(inner_xml.strip)
        title.xpath(".//unitdate").remove
        obj.title = format_content( title.to_xml(:encoding => 'utf-8') )
      end
    end
  end
with 'unitdate' do |node|
  next ignore if @ignore
   norm_dates = (att('normal') || "").sub(/^\s/, '').sub(/\s$/, '').split('/')
   if norm_dates.length == 1
     norm_dates[1] = norm_dates[0]
   end
   norm_dates.map! {|d| d =~ /^([0-9]{4}(\-(1[0-2]|0[1-9])(\-(0[1-9]|[12][0-9]|3[01]))?)?)$/ ? d : nil}
   make :date, {
     :date_type => att('type') || 'inclusive',
     :expression => inner_xml,
     :label => 'creation',
     :begin => norm_dates[0],
     :end => norm_dates[1],
     :calendar => att('calendar'),
     :era => att('era'),
     :certainty => att('certainty')
   } do |date|
     set ancestor(:resource, :archival_object), :dates, date
   end
 end
 with 'dimensions' do |node|
     next ignore if @ignore
     unless context == :note_orderedlist
     content = inner_xml.tap {|xml|
       xml.sub!(/<head>.*?<\/head>/m, '')
       # xml.sub!(/<list [^>]*>.*?<\/list>/m, '')
       # xml.sub!(/<chronlist [^>]*>.*<\/chronlist>/m, '')
     }
     make :note_multipart, {
       :type => node.name,
       :persistent_id => att('id'),
       :subnotes => {
         'jsonmodel_type' => 'note_text',
         'content' => format_content( content )
       }
     } do |note|
       set ancestor(:resource, :archival_object), :notes, note
     end
 end
end
 %w(accessrestrict accessrestrict/legalstatus \
   accruals acqinfo altformavail appraisal arrangement \
   bioghist custodhist \
   fileplan odd otherfindaid originalsloc phystech \
   prefercite processinfo relatedmaterial scopecontent \
   separatedmaterial userestrict ).each do |note|
  with note do |node|
    content = inner_xml.tap {|xml|
      xml.sub!(/<head>.*?<\/head>/m, '')
      # xml.sub!(/<list [^>]*>.*?<\/list>/m, '')
      # xml.sub!(/<chronlist [^>]*>.*<\/chronlist>/m, '')
    }
    make :note_multipart, {
      :type => node.name,
      :persistent_id => att('id'),
      :subnotes => {
        'jsonmodel_type' => 'note_text',
        'content' => format_content( content )
      }
    } do |note|
      set ancestor(:resource, :archival_object), :notes, note
    end
  end
end
# START RIGHTS STATEMENTS
# The stock ASpace EAD importer only makes "Conditions Governing Access" notes out of <accessrestrict> tags
# We want to also import our <accessrestrict> tags that have a restriction end date as a "Rights Statements"
# Let ArchivesSpace do its normal thing with accessrestrict
    %w(accessrestrict accessrestrict/legalstatus \
       accruals acqinfo altformavail appraisal arrangement \
       bioghist custodhist dimensions \
       fileplan odd otherfindaid originalsloc phystech \
       prefercite processinfo relatedmaterial scopecontent \
       separatedmaterial userestrict ).each do |note|
      with note do |node|
        content = inner_xml.tap {|xml|
          xml.sub!(/<head>.*?<\/head>/m, '')
          # xml.sub!(/<list [^>]*>.*?<\/list>/m, '')
          # xml.sub!(/<chronlist [^>]*>.*<\/chronlist>/m, '')
        }
        make :note_multipart, {
          :type => node.name,
          :persistent_id => att('id'),
          :subnotes => {
            'jsonmodel_type' => 'note_text',
            'content' => format_content( content )
          }
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
      end
    end
# Now make a Rights Statement using the content from the "Conditions Governing Access" note
# and the restriction end date from the accessrestrict/date
with 'accessrestrict/date' do
    ancestor(:archival_object) do |ao|
        ao.notes.each do |n|
            if n['type'] == 'accessrestrict'
                n['subnotes'].each do |sn|
                make :rights_statement, {
                :rights_type => 'institutional_policy',
                :restrictions => sn['content'],
                :restriction_end_date => att('normal')
                } do |rights|
                set ancestor(:resource, :archival_object), :rights_statements, rights
                end
                end
            end
        end
    end
end
=end

end
