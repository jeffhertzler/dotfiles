--
--
--          _|  _|    _|
--          _|  _|    _|      Jeff Hertzler
--          _|  _|_|_|_|      https://github.com/jeffhertzler
--    _|    _|  _|    _|      http://jeffhertzler.com
--      _|_|    _|    _|
--

-- this bit disables the lua module cache
package.loaded['helpers']  = nil
package.loaded['plugins']  = nil
package.loaded['settings'] = nil
package.loaded['keymaps']  = nil

require 'helpers'
require 'plugins'
require 'settings'
require 'keymaps'
