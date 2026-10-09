export async function requestMembership(config, action, fields) {
  if(action==='register'&&fields.password_confirmation!==fields.password){const error=new Error('Password confirmation does not match');error.code='password_mismatch';throw error;}
  const response = await fetch(`${config.supabaseUrl}/functions/v1/membership-auth`, {
    method:'POST',
    headers:{apikey:config.supabasePublishableKey,'Content-Type':'application/json'},
    body:JSON.stringify({action,...fields}),
    signal:AbortSignal.timeout(20000)
  });
  const result = await response.json();
  if (!response.ok) {
    const error = new Error('Membership request failed');
    error.code = result.code || 'unavailable';
    throw error;
  }
  return result;
}
