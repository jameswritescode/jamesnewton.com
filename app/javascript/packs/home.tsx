import { hot } from 'react-hot-loader/root'

import Home from '~mounts/Home'
import { mount, withProviders } from '~helpers/rendering'

mount(withProviders(hot(Home)))
