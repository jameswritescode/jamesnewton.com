import * as ActiveStorage from '@rails/activestorage'
import Home from '~mounts/Home'
import { mount, withProviders } from '~helpers/rendering'

ActiveStorage.start()

mount(withProviders(Home))
