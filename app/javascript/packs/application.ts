import 'channels'
import * as ActiveStorage from '@rails/activestorage'
import * as Ujs from '@rails/ujs'
import Home from '~mounts/Home'
import { mount, withProviders } from '~helpers/rendering'

Ujs.start()
ActiveStorage.start()

mount(withProviders(Home))
