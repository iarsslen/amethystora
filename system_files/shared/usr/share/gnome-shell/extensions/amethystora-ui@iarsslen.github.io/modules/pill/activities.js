// What is happening now, in the order the pill shows it: only the first that runs is in the pill, the next three are
// rows of its card. Things that wait for the person come before things that run in the background, so that music
// playing all afternoon never hides a call, a link or the battery's question.
//
// An activity is an object the part that runs it makes and keeps:
//   id            one of ORDER
//   pill()        its content in the pill (an actor the activity owns, made once and updated in place)
//   text          the pill's words, as shown (for the suites)
//   accessible    the pill in words, for a screen reader
//   row           {icon, text}: its row among the others in a card
//   card(api)     a new actor with its part of the card; api.close() closes the card
//   plate         '' or the plate's own look: 'link', 'battery', 'saver', 'quiet', 'focus'
//   activate()    optional: what a click on the pill's body does instead of opening the card
//
// A focus profile's mark (modules/focus/mark.js) comes last: it says what the desktop is set to, not what happens.

export const ORDER = ['call', 'recording', 'link', 'battery', 'waiting', 'timer', 'media', 'update', 'quiet', 'focus'];

// At most this many others are listed in a card
const OTHERS = 3;

export class Activities {
    constructor(changed) {
        this._changed = changed;
        this._running = new Map();
    }

    // Starts, replaces or (with null) ends the activity of this id
    set(id, activity) {
        if (!ORDER.includes(id))
            throw new Error(`no activity ${id}`);
        const before = this._running.get(id) ?? null;
        if (activity)
            this._running.set(id, activity);
        else
            this._running.delete(id);
        if (before !== activity)
            this._changed?.();
    }

    get(id) {
        return this._running.get(id) ?? null;
    }

    // Something an activity shows changed (its words, and so perhaps its width)
    update(id) {
        if (this._running.has(id))
            this._changed?.(id);
    }

    get list() {
        return ORDER.filter(id => this._running.has(id)).map(id => this._running.get(id));
    }

    get top() {
        return this.list[0] ?? null;
    }

    get others() {
        return this.list.slice(1, 1 + OTHERS);
    }

    clear() {
        this._running.clear();
        this._changed = null;
    }
}
