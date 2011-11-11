Introduction
============

IMPORTANT: Backup your original `collection.json` file before running 
this script!

This is a simple ruby script to automatically classify documents in 
kindle collections based on the directory structure.

Collections are defined on basis of the second directory name. Examples:

<table>
<tr>
<th>Filename</th>
<th>Collection</th>
</tr>
<tr>
<td><code>documents/filename.ext</code></td>
<td>Such a file won't be added to a collection</td>
</tr>
<tr>
<td><code>documents/collection/filename.ext</code></td>
<td><code>collection</code></td>
</tr>
<tr>
<td><code>documents/collection/subdir/filename.ext</code></td>
<td><code>collection</code></td>
</tr>
</table>

For now, only Kindle version 2 (e.g. Kindle DX) is supported (i.e. 
tested). I have no idea if the script works for other versions.

Example usage:

    kindle_collections.rb --dir /media/Kindle

You have to hard reset the kindle for the changes to take effect.


Installation
============

Copy or symlink `kindle_collections.rb` to a directory in $PATH.


Configuration
=============

The script can be configured via YAML files that is searched in:

- `/etc/kindle_collections.yml`
- `$HOME/.kindle_collections.yml`
- `$HOME/.kindle_collections_$HOSTNAME.yml`
- `Windows: %USERPROFILE%/kindle_collections.yml`

Each command-line option can be configured via this YAML file.

Example configuration file:

    --- 
    dir: /media/Kindle
    rx: !ruby/regexp /\.(azw|mobi|txt|pdf)$/
    subdirs: 
    - documents

An initial configuration file can be created with the following command:

    kindle_collections.rb --print-config > ~/.kindle_collections.yml


Collection patterns
-------------------

Files can also be added to collections based on regular expressions. 
This can be achieved by adding a `collection_patterns` section to the 
YAML file.

Example:

    collection_patterns: 
      news:
      - ^documents/newsfeeds/lemonde\.fr/
      - ^documents/misc/nytimes\.com/
      tech:
      - ^documents/newsfeeds/heise\.de/


Known Problems
==============

ATM certain files cannot be properly added to collections. This problem 
affects filenames that include underscores ("\_"). In order to avoid 
this problem, users can pass a template JSON file to 
`kindle_collections.rb`:

    kindle_collections.rb --json /media/Kindle/system/collections_base.json

In order to get such a base JSON file, proceed as follows:

1. Connect the kindle to your computer
2. Run `kindle_collections.rb`
3. Disconnect the kindle
4. Hard-reset the kindle
5. Add the missing documents to collections
6. Connect the kindle to your computer
7. `cd /media/Kindle/system`
9. Run `kindle_collections.rb --print-diff collections.json > collections_base.json`


Requirements
============

- Ruby 1.8
- json gem


Licence
=======

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see http://www.gnu.org/licenses/

