import 'package:flutter/material.dart';
import '../models/event.dart';
import '../services/enhanced_event_service.dart';

class CreateEventScreen extends StatefulWidget {
  final String organizerId;
  final VoidCallback onEventCreated;
  // If provided, the screen runs in edit mode
  final Event? existingEvent;

  const CreateEventScreen({
    super.key,
    required this.organizerId,
    required this.onEventCreated,
    this.existingEvent,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final EnhancedEventService _eventService = EnhancedEventService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  late TextEditingController _dateTimeController;
  DateTime? _selectedDateTime;
  bool _isLoading = false;

  bool get _isEditMode => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    _dateTimeController = TextEditingController();

    // Pre-fill if editing
    if (_isEditMode) {
      final e = widget.existingEvent!;
      _nameController.text = e.name;
      _descriptionController.text = e.description;
      _locationController.text = e.location;
      _capacityController.text = e.capacity.toString();
      _priceController.text = e.ticketPrice.toString();
      _selectedDateTime = e.eventDate;
      _dateTimeController.text = e.eventDate.toString().split('.')[0];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _capacityController.dispose();
    _priceController.dispose();
    _dateTimeController.dispose();
    super.dispose();
  }

  void _selectDateTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime(2030),
    );

    if (picked != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: _selectedDateTime != null
            ? TimeOfDay.fromDateTime(_selectedDateTime!)
            : TimeOfDay.now(),
      );

      if (time != null && mounted) {
        final selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );

        setState(() {
          _selectedDateTime = selectedDateTime;
          _dateTimeController.text = selectedDateTime.toString().split('.')[0];
        });
      }
    }
  }

  void _saveEvent() async {
    if (_capacityController.text.isEmpty ||
        int.tryParse(_capacityController.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid capacity (number)')),
      );
      return;
    }

    if (_priceController.text.isEmpty ||
        double.tryParse(_priceController.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid ticket price')),
      );
      return;
    }

    if (_nameController.text.isEmpty ||
        _descriptionController.text.isEmpty ||
        _locationController.text.isEmpty ||
        _selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isEditMode) {
        // Update existing event
        await _eventService.updateEvent(
          eventId: widget.existingEvent!.id,
          name: _nameController.text,
          description: _descriptionController.text,
          eventDate: _selectedDateTime,
          location: _locationController.text,
          capacity: int.parse(_capacityController.text),
          ticketPrice: double.parse(_priceController.text),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Event updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onEventCreated();
          Navigator.pop(context, true);
        }
      } else {
        // Create new event
        await _eventService.createEvent(
          organizerId: widget.organizerId,
          name: _nameController.text,
          description: _descriptionController.text,
          eventDate: _selectedDateTime!,
          location: _locationController.text,
          capacity: int.parse(_capacityController.text),
          ticketPrice: double.parse(_priceController.text),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Event created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onEventCreated();
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Event' : 'Create Event'),
        backgroundColor: Colors.deepPurple,
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTextInputField(
              controller: _nameController,
              label: 'Event Name *',
              hint: 'Enter event name',
              icon: Icons.event,
            ),
            const SizedBox(height: 16),
            _buildTextInputField(
              controller: _descriptionController,
              label: 'Description *',
              hint: 'Enter event description',
              icon: Icons.description,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _buildTextInputField(
              controller: _locationController,
              label: 'Venue / Location *',
              hint: 'Enter event location',
              icon: Icons.location_on,
            ),
            const SizedBox(height: 16),
            _buildTextInputField(
              controller: _capacityController,
              label: 'Maximum Capacity (optional)',
              hint: 'Enter maximum attendees',
              icon: Icons.people,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildTextInputField(
              controller: _priceController,
              label: 'Ticket Price',
              hint: 'Enter ticket price (0 for free)',
              icon: Icons.attach_money,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            // Date & Time Picker
            TextField(
              controller: _dateTimeController,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: 'Event Date & Time *',
                labelStyle: const TextStyle(
                  color: Colors.deepPurple,
                  fontWeight: FontWeight.bold,
                ),
                hintText: 'Tap to select date and time',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.calendar_today, color: Colors.deepPurple),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                ),
                suffixIcon: GestureDetector(
                  onTap: _selectDateTime,
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(Icons.calendar_month, color: Colors.deepPurple),
                  ),
                ),
              ),
              readOnly: true,
              onTap: _selectDateTime,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveEvent,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        _isEditMode ? Icons.save : Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                label: Text(
                  _isLoading
                      ? (_isEditMode ? 'UPDATING...' : 'CREATING...')
                      : (_isEditMode ? 'SAVE / PUBLISH' : 'CREATE EVENT'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade700,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.deepPurple,
          fontWeight: FontWeight.bold,
        ),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.deepPurple),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}