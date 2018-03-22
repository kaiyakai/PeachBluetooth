//
//  InterfaceController.swift
//  BluetoothCentral WatchKit Extension
//
//  Created by Nikolay Dakov on 20/02/2018.
//  Copyright © 2018 Nikolay Dakov. All rights reserved.
//

import WatchKit
import Foundation
import HealthKit
import CoreBluetooth

class InterfaceController: WKInterfaceController {
    
    // Bluetooth variables
    @IBOutlet var statusLabel: WKInterfaceLabel!
    
    let TextOrMapServiceUUID = CBUUID(string: "0000fff0-0000-1000-8000-00805f9b34fb")
    let textCharacteristicUUID = CBUUID(string: "0000fff1-0000-1000-8000-00805f9b34fb")
    let heartCharacteristicUUID = CBUUID(string:
        "0000fff2-0000-1000-8000-00805f9b34fb")
    let RSSI_range = -40..<(-15)  // optimal -22dB
    
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral?
    var textCharacteristic: CBCharacteristic?
    var data = Data()
    var heartCharacteristic: CBCharacteristic?
    
    // Heart rate variables
    @IBOutlet var heartLabel: WKInterfaceLabel!
    @IBOutlet var startStopButton: WKInterfaceButton!
    
    let healthStore = HKHealthStore()
    
    //State of the app - is the workout activated
    var workoutActive = false
    
    // define the activity type and location
    var workoutSession : HKWorkoutSession?
    let heartRateUnit = HKUnit(from: "count/min")
    var anchor = HKQueryAnchor(fromValue: Int(HKAnchoredObjectQueryNoAnchor))
    
    func button() {
        guard let characteristic = heartCharacteristic else { return }
        let random = UInt8(arc4random_uniform(7) + 60)
        discoveredPeripheral?.writeValue(Data(bytes: [random]), for: characteristic, type: .withoutResponse)
    }
    
    @objc func send() {
        guard let characteristic = heartCharacteristic else { return }
        let random = UInt8(arc4random_uniform(7) + 60)
        heartLabel.setText(String(random))
        discoveredPeripheral?.writeValue(Data(bytes: [random]), for: characteristic, type: .withoutResponse)
    }
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        centralManager = CBCentralManager(delegate: self, queue: nil)
        _ = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(self.send), userInfo: nil, repeats: true)
        // Configure interface objects here.
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
        
        guard HKHealthStore.isHealthDataAvailable() == true else {
            heartLabel.setText("not available")
            return
        }
        
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else {
            displayNotAllowed()
            return
        }
        
        let dataTypes = Set(arrayLiteral: quantityType)
        healthStore.requestAuthorization(toShare: nil, read: dataTypes) { (success, error) -> Void in
            if success == false {
                self.displayNotAllowed()
            }
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        switch toState {
        case .running:
            workoutDidStart(date)
        case .ended:
            workoutDidEnd(date)
        default:
            print("Unexpected state \(toState)")
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        // Do nothing for now
        // NSLog("Workout error: \(error.userInfo)")
    }
    
    func workoutDidStart(_ date : Date) {
        if let query = createHeartRateStreamingQuery(date) {
            healthStore.execute(query)
        } else {
            heartLabel.setText("cannot start")
        }
    }
    
    func workoutDidEnd(_ date : Date) {
        if let query = createHeartRateStreamingQuery(date) {
            healthStore.stop(query)
            heartLabel.setText("---")
        } else {
            heartLabel.setText("cannot stop")
        }
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
    
    func displayNotAllowed() {
        heartLabel.setText("not allowed")
    }
    
    func startStopBtnClicked() {
        if (self.workoutActive) {
            //finish the current workout
            self.workoutActive = false
            self.startStopButton.setTitle("Start")
            if let workout = self.workoutSession {
                healthStore.end(workout)
            }
        } else {
            //start a new workout
            self.workoutActive = true
            self.startStopButton.setTitle("Stop")
            startWorkout()
        }
    }
    
    
    func startWorkout() {
        self.workoutSession = HKWorkoutSession(activityType: HKWorkoutActivityType.crossTraining, locationType: HKWorkoutSessionLocationType.indoor)
        self.workoutSession?.delegate = self as! HKWorkoutSessionDelegate
        healthStore.start(self.workoutSession!)
    }
    
    func createHeartRateStreamingQuery(_ workoutStartDate: Date) -> HKQuery? {
        // adding predicate will not work
        // let predicate = HKQuery.predicateForSamplesWithStartDate(workoutStartDate, endDate: nil, options: HKQueryOptions.None)
        
        guard let quantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else { return nil }
        
        let heartRateQuery = HKAnchoredObjectQuery(type: quantityType, predicate: nil, anchor: anchor, limit: Int(HKObjectQueryNoLimit)) { (query, sampleObjects, deletedObjects, newAnchor, error) -> Void in
            guard let newAnchor = newAnchor else {return}
            self.anchor = newAnchor
            self.updateHeartRate(sampleObjects)
        }
        
        heartRateQuery.updateHandler = {(query, samples, deleteObjects, newAnchor, error) -> Void in
            self.anchor = newAnchor!
            self.updateHeartRate(samples)
        }
        return heartRateQuery
    }
    
    func updateHeartRate(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample] else {return}
        
        DispatchQueue.main.async {
            guard let sample = heartRateSamples.first else{return}
            let value = sample.quantity.doubleValue(for: self.heartRateUnit)
            self.heartLabel.setText(String(UInt16(value)))
            
        }
    }
    
    // MARK: - Helper methods
    
    func scan() {
        statusLabel.setText("scanning")
        centralManager.scanForPeripherals(withServices: [TextOrMapServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true as Bool)])
    }
    
    func cleanup() {
        guard discoveredPeripheral?.state != .disconnected,
            let services = discoveredPeripheral?.services else {
                centralManager.cancelPeripheralConnection(discoveredPeripheral!)
                return
        }
        for service in services {
            if let characteristics = service.characteristics {
                for characteristic in characteristics {
                    if characteristic.uuid.isEqual(textCharacteristicUUID) {
                        if characteristic.isNotifying {
                            discoveredPeripheral?.setNotifyValue(false, for: characteristic)
                            return
                        }
                    }
                }
            }
        }
        centralManager.cancelPeripheralConnection(discoveredPeripheral!)
    }
}

// MARK: - Central Manager delegate
extension InterfaceController: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: scan()
        case .poweredOff, .resetting: cleanup()
        default: return
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard RSSI_range.contains(RSSI.intValue) && discoveredPeripheral != peripheral else { return }
        statusLabel.setText("discovered peripheral")
        discoveredPeripheral = peripheral
        central.connect(peripheral, options: [:])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error { print(error.localizedDescription) }
        cleanup()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        statusLabel.setText("connected to peripheral")
        central.stopScan()
        data.removeAll()
        peripheral.delegate = self
        peripheral.discoverServices([TextOrMapServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if (peripheral == discoveredPeripheral) {
            cleanup()
        }
        scan()
    }
    
}

// MARK: - Peripheral Delegate
extension InterfaceController: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            cleanup()
            return
        }
        
        guard let services = peripheral.services else { return }
        for service in services {
            statusLabel.setText("discovered service")
            peripheral.discoverCharacteristics([textCharacteristicUUID, heartCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            cleanup()
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == textCharacteristicUUID {
                statusLabel.setText("discovered textCharacteristic")
                textCharacteristic = characteristic
            } else if characteristic.uuid == heartCharacteristicUUID {
                statusLabel.setText("discovered mapCharacteristic")
                heartCharacteristic = characteristic
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            return
        }
        
        if characteristic == textCharacteristic {
            guard let newData = characteristic.value else { return }
            let stringFromData = String(data: newData, encoding: .utf8)
            statusLabel.setText("received \(stringFromData ?? "nothing")")
            
            if stringFromData == "EOM" {
                statusLabel.setHidden(true)
                //textLabel.setText(String(data: data, encoding: .utf8))
                data.removeAll()
            } else {
                data.append(newData)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { print(error.localizedDescription) }
        guard characteristic.uuid == textCharacteristicUUID else { return }
        if characteristic.isNotifying {
            print("Notification began on \(characteristic)")
        } else {
            print("Notification stopped on \(characteristic). Disconnecting...")
        }
    }
    
    // Stub to stop run-time warning
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {}
}

