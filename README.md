BHL EAD Importer
================
Custom ArchivesSpace EAD Importer for Bentley Historical Library EADs

Basic Info
----------
This is an ArchivesSpace plug-in and can be installed following the directions on the [ArchivesSpace Plug-ins README](https://github.com/archivesspace/archivesspace/tree/master/plugins).

The plug-in adds a new importer to the application with the id "bhl_ead_xml". This is a subclass of the standard EAD importer that ships with ArchivesSpace 1.1.2.

The custom importer does the following:

  1. Does some basic cleanup (with commas, spaces, &c.).
  2. Creates digital object titles---when they don't exist in the EAD---based on the parent archival object's title and date(s) so that records import.
  3. Imports index entries with their values and reference texts within the same index item, rather than splitting them into separate items.
  4. Makes a rights statement using the content from the Conditions Governing Access note, normalizing the restriction end date.
  
These customizations are specific to version 1.1.2 of ArchivesSpace and may not work with later versions.

These customizations are also a work in progress. We will be continue to add more customizations as we identify issues and possible solutions for importing our legacy EADs into ArchivesSpace. 

Acknowledgements
----------------
We were inspired by Chris Fitzpatrick's [post](https://archivesspace.atlassian.net/wiki/pages/viewpage.action;jsessionid=B61CF1FF951457641EDB06B6FAA9C599?pageId=18088140) on customizing ArchivesSpace EAD importers and exporters.