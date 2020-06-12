import { hot } from 'react-hot-loader/root'

import Blog from '~mounts/Blog'
import { withProviders, mount } from '~helpers/rendering'

mount(withProviders(hot(Blog)))
