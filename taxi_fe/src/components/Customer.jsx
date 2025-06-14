import React, { useEffect, useState } from 'react';
import Button from '@mui/material/Button';
import { TextField } from '@mui/material';
import socket from '../services/taxi_socket';

function Customer(props) {
  const [pickupAddress, setPickupAddress] = useState("Tecnologico de Monterrey, campus Puebla, Mexico");
  const [dropOffAddress, setDropOffAddress] = useState("Triangulo Las Animas, Puebla, Mexico");
  const [msg, setMsg] = useState("");
  const [msg1, setMsg1] = useState("");
  const [statusMsg, setStatusMsg] = useState("");
  const [phase, setPhase] = useState("idle"); // idle | looking | accepted | failed
  const [lookingTimer, setLookingTimer] = useState(60); // 1 minute
  const [arrivalTimer, setArrivalTimer] = useState(480); // 8 minutes

  useEffect(() => {
    const channel = socket.channel("customer:" + props.username, { token: "123" });

    channel.on("greetings", data => console.log(data));

    channel.on("booking_request", dataFromPush => {
      console.log("Received", dataFromPush);
      setMsg1(dataFromPush.msg);
      setPhase("accepted");
      setArrivalTimer(480);
    });

    channel.on("booking_failed", _ => {
      setPhase("failed");
      setStatusMsg("Can't find drivers. Try again later.");
    });

    channel.join();

    return () => {
      channel.leave();
    };
  }, [props.username]);

  useEffect(() => {
    if (phase === "looking" && lookingTimer > 0) {
      const interval = setInterval(() => {
        setLookingTimer(t => t - 1);
      }, 1000);
      return () => clearInterval(interval);
    }
    if (phase === "looking" && lookingTimer === 0) {
      // Optional: could emit cancel event here or wait for backend
      setPhase("failed");
      setStatusMsg("Can't find drivers. Try again later.");
    }
  }, [phase, lookingTimer]);

  useEffect(() => {
    if (phase === "accepted" && arrivalTimer > 0) {
      const interval = setInterval(() => {
        setArrivalTimer(t => t - 1);
      }, 1000);
      return () => clearInterval(interval);
    }
    if (phase === "accepted" && arrivalTimer === 0) {
      setStatusMsg("Driver should have arrived.");
    }
  }, [phase, arrivalTimer]);

  const submit = () => {
    setMsg("");
    setMsg1("");
    setPhase("looking");
    setLookingTimer(60);
    setStatusMsg("Looking for driver...");

    fetch(`http://localhost:4000/api/bookings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pickup_address: pickupAddress,
        dropoff_address: dropOffAddress,
        username: props.username
      })
    })
      .then(resp => resp.json())
      .then(dataFromPOST => setMsg(dataFromPOST.msg));
  };

  const renderTimeHandlerText = () => {
    switch (phase) {
      case "looking":
        return `Looking for driver... (${lookingTimer}s)`;
      case "accepted":
        const min = Math.floor(arrivalTimer / 60);
        const sec = String(arrivalTimer % 60).padStart(2, '0');
        return `Your driver will arrive in ${min}:${sec}`;
      case "failed":
        return "Can't find drivers. Try again later.";
      default:
        return "Waiting for request...";
    }
  };

  return (
    <div style={{ textAlign: "center", borderStyle: "solid" }}>
      <div>Customer: {props.username}</div>
      <div>
        <TextField
          id="pickup"
          label="Pickup address"
          fullWidth
          onChange={e => setPickupAddress(e.target.value)}
          value={pickupAddress}
        />
        <TextField
          id="dropoff"
          label="Drop off address"
          fullWidth
          onChange={e => setDropOffAddress(e.target.value)}
          value={dropOffAddress}
        />
        <Button onClick={submit} variant="outlined" color="primary">
          Submit
        </Button>
      </div>

      <div style={{ backgroundColor: "lightcyan", height: "50px" }}>{msg}</div>
      <div style={{ backgroundColor: "lightblue", height: "50px" }}>{msg1}</div>
      <div style={{ backgroundColor: "lightyellow", height: "50px" }}>{renderTimeHandlerText()}</div>
    </div>
  );
}

export default Customer;
