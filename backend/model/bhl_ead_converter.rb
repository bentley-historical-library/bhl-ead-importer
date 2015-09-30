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
  	return content if content.nil?
    content.delete!("\n") # first we remove all linebreaks, since they're probably unintentional
    content.gsub("<p>","").gsub("</p>","\n\n" ).gsub("<p/>","\n\n")
  		   .gsub("<lb/>", "\n\n").gsub("<lb>","\n\n").gsub("</lb>","").gsub(/[\s,]+$/,"") # also remove trailing commas
  	     .strip
  end


  def self.configure
    super

# BEGIN CONDITIONAL SKIPS

# We have lists and indexes with all sorts of crazy things, like <container>, <physdesc>, <physloc>, etc. tags within <item>  or <ref> tags
# So, we need to tell the importer to skip those things only when they appear in places where they shouldn't, otherwise do
# it's normal thing

%w(abstract langmaterial materialspec physfacet physloc).each do |note|
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
          :content => format_content( content.sub(/<head>.*?<\/head>/, '') )
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
      end
    end

with 'list' do
      next if ancestor(:note_index) # skip these
      if  ancestor(:note_multipart)
        left_overs = insert_into_subnotes
	  else
        left_overs = nil
        make :note_multipart, {
          :type => 'odd',
          :persistent_id => att('id'),
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

# END CONDITIONAL SKIPS


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
      'subject' => 'topical'
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
        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'subject', 'terms' => terms}
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

        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'subject', 'terms' => terms}
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

        if att('ref')
            set ancestor(:resource, :archival_object), :linked_agents, {'ref' => att('ref'), 'role' => 'subject', 'terms' => terms}
        else
            make_person_template(:role => 'subject')
        end
    end

# END CUSTOM SUBJECT AND AGENT IMPORTS


# BEGIN PHYSDESC CUSTOMIZATIONS

# The stock EAD importer doesn't import <physfacet> and <dimensions> tags into extent objects; instead making them notes
# This is a corrected version
 with 'physdesc' do
      next if context == :note_orderedlist # skip these
      physdesc = Nokogiri::XML::DocumentFragment.parse(inner_xml)
      extent_number_and_type = nil
      dimensions = nil
      physfacet = nil
      other_extent_data = []
      make_note_too = false

      # We want the EAD importer to know when we're importing partial extents, which following ASpace practice is indicated by "altrender" attribute
      portion = att('altrender') || 'whole'

      physdesc.children.each do |child|
        if child.name == 'extent'
          child_content = child.content.strip
          if extent_number_and_type.nil? && child_content =~ /^([0-9\.]+)+\s+(.*)$/
            extent_number_and_type = {:number => $1, :extent_type => $2}
          else
            other_extent_data << child_content
          end

        elsif child.name == 'physfacet'
          child_content = child.content.strip
          physfacet = child_content

        elsif child.name == 'dimensions'
          child_content = child.content.strip
          dimensions = child_content

        else
          # there's other info here; make a note as well
          make_note_too = true unless child.text.strip.empty?
        end
      end

      # only make an extent if we got a number and type, otherwise put all physdesc contents into a note
      if extent_number_and_type
        make :extent, {
          :number => $1,
          :extent_type => $2,
          :portion => portion,
          :container_summary => other_extent_data.join('; '),
          :physical_details => physfacet,
          :dimensions => dimensions
        } do |extent|
          set ancestor(:resource, :archival_object), :extents, extent
        end
      else
        make_note_too = true;
      end

      if make_note_too
        content =  physdesc.to_xml(:encoding => 'utf-8')
        make :note_singlepart, {
          :type => 'physdesc',
          :persistent_id => att('id'),
          :content => format_content( content.sub(/<head>.*?<\/head>/, '').strip )
        } do |note|
          set ancestor(:resource, :archival_object), :notes, note
        end
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

# This forms a title string using the parent archival object's title, if it exists
  daotitle = ''
  ancestor(:archival_object ) do |ao|
    if ao.title
      daotitle << ao.title
    else
      daotitle = nil
    end
  end

# This forms a date string using the parent archival object's date expression,
# or its begin date - end date, or just it's begin date, if any exist
  daodate = ''
  ancestor(:archival_object) do |aod|
    if aod.dates && aod.dates.length > 0
      aod.dates.each do |dl|
        if dl['expression'].length > 0
          daodate += ', ' if daodate.length > 0
          daodate += dl['expression']
        else
          daodate = nil
        end
      end
    end
  end

  title = daotitle
  date_label = daodate if daodate.length > 0

# This forms a display string using the parent archival object's title and date (if both exist),
# or just its title or date (if only one exists)
  display_string = title || ''
  display_string += ', ' if title && date_label
  display_string += date_label if date_label

  make :instance, {
    :instance_type => 'digital_object'
    } do |instance|
  set ancestor(:resource, :archival_object), :instances, instance
  end

# We'll use either the <dao> title attribute (if it exists) or our display_string (if the title attribute does not exist)
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

# END DAO TITLE CUSTOMIZATIONS





=begin
# Note: The following bits are here for historical reasons
# We have either decided against implementing the functionality OR the ArchivesSpace importer has changed, deprecating the following customizations

#BEGIN IGNORE
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

#BEGIN RIGHTS STATEMENTS
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
