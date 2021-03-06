package ext.swizframework.processors
{
	import ext.swizframework.events.StateEvent;
	import ext.swizframework.events.StateChangeHandler;
	import ext.swizframework.metadata.StateChangeMetadataTag;
	import ext.swizframework.metadata.StateChangeExpression;
	import ext.swizframework.model.StateChangeHandlers;

	import flash.events.IEventDispatcher;

	import org.swizframework.core.Bean;
	import org.swizframework.core.SwizConfig;
	import org.swizframework.processors.BaseMetadataProcessor;
	import org.swizframework.reflection.IMetadataTag;
	import org.swizframework.utils.logging.SwizLogger;

	/**
     * StateChange provides easy handling for changes to state within a Swiz application. Working
	 * essentially the same as an EventHandler but filtered based on a given states, the StateChange
	 * is triggered any time a StateEvent.STATE_CHANGE reaches the Swiz global event dispatcher.
	 *
	 * When the StateEvent is received, the processor will route the event to the designated state event handlers
	 * as noted by their metadata:
	 *
	 * [StateChange(state="login")]
	 * public function changeToLogin():void
	 * {
	 *
	 * }
	 *
	 * The above example will be called anytime a StateEvent with a state property of "login" is dispatched. State is
	 * the default parameter to the StateChange tag so [StateChange("login")] can be used as well.
	 *
	 * The processor will also detect the parameters for the state handler method. If no parameters exist then the handler method
	 * will be called without parameters. However, if the method contains a parameter of type StateEvent, then the event will
	 * be passed to the handler. StateEvents also have a property called "parameters". If the handler has a parameter of type Object,
	 * then the parameters value will be passed to the handler.
	 *
	 * [StateChange(state="login")]
     * public function changeToLogin(event:StateEvent):void
     * {
     *
     * }
	 *
	 * or
	 *
	 * [StateChange(state="login")]
     * public function changeToLogin(parameters:Object):void
     * {
     *
     * }
	 *
	 * StateChanges can also be noted at the top of a class and use an optional "handler" parameter. The handler param
	 * is the string name of the method within the class to use as a handler. This method will not allow for the method parameter
	 * detect and will always call the handler without parameters.
	 *
	 * [StateChange(state="login", handler="changeToLogin")]
	 *
	 * public class LoginViewStateModel
	 * {
	 *      public function changeToLogin():void
	 *      {
	 *
	 *      }
	 * }
	 *
	 * The StateChange tag also has an option priority parameter that allows you to set priority of the handlers. 0 being the highest,
	 * handlers filtered by identical state names will be called in order of priority.
	 *
	 * @author jeppesen
     */
    public class StateChangeProcessor extends BaseMetadataProcessor
    {
        private static const STATE_CHANGE:String = "StateChange";

        private const logger:SwizLogger = SwizLogger.getLogger(this);

        private const handlers:StateChangeHandlers = new StateChangeHandlers();

        public var statePackages:Array = [];

        /**
         * @inheritDoc
         */
        override public function get priority():int
        {
            return 0;
        }

        /**
         * Reference to the swiz event dispatcher
         */
        public function get dispatcher():IEventDispatcher
        {
            return swiz.config.defaultDispatcher == SwizConfig.LOCAL_DISPATCHER ? swiz.dispatcher : swiz.globalDispatcher;
        }

        public function StateChangeProcessor(metadataNames:Array = null, statePackages:Array = null)
        {
            super((metadataNames == null) ? [ STATE_CHANGE ] : metadataNames, StateChangeMetadataTag);
            this.statePackages = statePackages || [ ];
        }

        /**
         * @inheritDoc
         */
        override public function setUpMetadataTag(metadataTag:IMetadataTag, bean:Bean):void
        {
            super.setUpMetadataTag(metadataTag, bean);

            var eventHandlerTag:StateChangeMetadataTag = metadataTag as StateChangeMetadataTag;

            if (validateEventHandlerMetadataTag(eventHandlerTag, bean))
            {
                var expression:StateChangeExpression = new StateChangeExpression(eventHandlerTag.state, swiz, statePackages);
                var view:String = expression.state;
                var handler:String = eventHandlerTag.handler;
                var handlerFn:Function = getHandlerFunction(handler, bean);

                if (handlerFn == null && eventHandlerTag.host)
                    handlerFn = getHandlerFunction(eventHandlerTag.host.name, bean);

                logger.debug("Adding handler {0} on {1} for view {2}({3})", handler, bean.toString(), view, eventHandlerTag.state);

                handlers.addHandler(new StateChangeHandler(view, handlerFn, eventHandlerTag, priority));

                if (handlers.handlerCount == 1)
                    dispatcher.addEventListener(StateEvent.STATE_CHANGE, handleStateChangeEvents);

                logger.debug("StateChangeProcessor set up {0} on {1}", metadataTag.toString(), bean.toString());
            }
        }

        /**
         * @inheritDoc
         */
        override public function tearDownMetadataTag(metadataTag:IMetadataTag, bean:Bean):void
        {
            super.tearDownMetadataTag(metadataTag, bean);

            var eventHandlerTag:StateChangeMetadataTag = metadataTag as StateChangeMetadataTag;

            var expression:StateChangeExpression = new StateChangeExpression(eventHandlerTag.state, swiz, statePackages);
            var view:String = expression.state;
            var handlerFn:Function = getHandlerFunction(eventHandlerTag.handler, bean);

            handlers.removeHandler(view, handlerFn);

            if (handlers.handlerCount == 0)
                dispatcher.removeEventListener(StateEvent.STATE_CHANGE, handleStateChangeEvents);

            logger.debug("StateChangeProcessor tear down {0} on {1}", metadataTag.toString(), bean.toString());
        }

        private function validateEventHandlerMetadataTag(eventHandlerTag:StateChangeMetadataTag, bean:Bean):Boolean
        {
            var state:String = eventHandlerTag.state;
            var handler:String = eventHandlerTag.handler ? eventHandlerTag.handler : eventHandlerTag.host.name;

            if (isEmpty(state))
            {
                throw new Error("Missing \"state\" property in [StateChange] tag: " + eventHandlerTag.asTag);
            }

            if (isEmpty(handler))
            {
                throw new Error("Missing \"handler\" property in [StateChange] tag: " + eventHandlerTag.asTag);
            }
            else
            {
                var handlerFn:Function = getHandlerFunction(handler, bean);

                if (handlerFn == null)
                {
                    throw new Error("Specified \"handler\" doesn't exist or is not a Function: " + eventHandlerTag.asTag);
                }
            }

            return true;
        }

        private function isEmpty(value:String):Boolean
        {
            return value == null || value.length == 0;
        }

        private function getHandlerFunction(handler:String, bean:Bean):Function
        {
            if (bean.source.hasOwnProperty(handler) && bean.source[handler] is Function)
            {
                return bean.source[handler];
            }

            return null;
        }

        private function handleStateChangeEvents(event:StateEvent):void
        {
            var handlersForView:Array = handlers.getHandlersForView(event.state);

            if (handlersForView)
            {
                for (var i:int = 0; i < handlersForView.length; i++)
                {
                    StateChangeHandler(handlersForView[i]).handleEvent(event);
                }
            }
            else
            {
                logger.warn("No handlers found for state change: {0}", event.state);
            }
        }
    }
}
