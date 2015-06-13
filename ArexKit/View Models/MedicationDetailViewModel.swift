import Monocle
import Pistachio
import ReactiveCocoa

public class MedicationDetailViewModel {
    private var medication: Medication
    private let medicationsController: MedicationsController
    public let form: MedicationDetailForm

    public init(medicationsController: MedicationsController, medication: Medication) {
        self.medication = medication
        self.medicationsController = medicationsController
        self.form = MedicationDetailForm(medication: medication)

        self.isNew = !get(MedicationLenses.isPersisted, medication)
        self._editing = MutableProperty(true)
        self.editing = PropertyOf(self._editing)

        let name = DynamicProperty(object: self.form, keyPath: "name")
        self.name = name.map { $0 as? String }

        // If `medication` is new, start in editing mode.
        self.canSave = self.name.map { name in
            return name.map { !$0.isEmpty } ?? false
        }

        self.beginEditing = Action(enabledIf: self._editing.map(!)) { _ in SignalProducer.empty }

        let revertEnabled = MutableProperty(true)
        self.revertChanges = Action(enabledIf: revertEnabled) { _ in SignalProducer.empty }

        // All properties have been initialized.

        self._editing.value = self.isNew
        self._editing.producer
            |> combineLatestWith(self.saveChanges.executing.producer)
            |> map { (editing, saving) in editing && !saving }
            |> start(Event.sink(next: revertEnabled.put))

        self.beginEditing.executing.producer
            |> filter(boolValue)
            |> start(next: { [unowned self] _ in
                self._editing.value = true
            })

        self.revertChanges.executing.producer
            |> filter(boolValue)
            |> start(next: { [unowned self] _ in
                self.form.medication = self.medication
                self._editing.value = false
            })
    }

    // MARK: Properties

    public let isNew: Bool
    private let _editing: MutableProperty<Bool>
    public let editing: PropertyOf<Bool>
    public let canSave: PropertyOf<Bool>
    public let name: PropertyOf<String?>

    public var isPersisted: Bool {
        return get(MedicationLenses.isPersisted, medication)
    }

    // MARK: Actions

    public let beginEditing: Action<Void, Void, NoError>
    public let revertChanges: Action<Void, Void, NoError>

    // This has to be a lazy var (vs let) because it references self.
    public private(set) lazy var saveChanges: Action<Void, Void, MedicationsControllerError> = {
        let onNext: Medication -> Void = { [unowned self] in self.medication = $0 }
        let onComplete: Void -> Void = { [unowned self] in self._editing.value = false }

        return Action(enabledIf: self.canSave) { [unowned self] _ in
            var medication = self.form.medication
            return self.medicationsController.save(medication: &medication)
                |> map { return undefined("Did not expect MedicationsController.save(_:) to send a next event") }
                |> concat(SignalProducer { observer, disposable in disposable += SignalProducer(value: medication).start(observer) })
                |> on(completed: onComplete, next: onNext)
                |> map(void)
        }
    }()
}

// MARK: - Lenses

private struct MedicationDetailViewModelLenses {
    static let medication = Lens(
        get: { $0.medication },
        set: { (inout viewModel: MedicationDetailViewModel, medication) in viewModel.medication = medication }
    )
}
